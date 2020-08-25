# app/controllers/gigs/inquiries_controller.rb

class Gigs::InquiriesController < Gigs::ApplicationController
  load_and_authorize_resource # https://github.com/CanCanCommunity/cancancan#32-loaders

  respond_to :html, only: [:new, :show]
  respond_to :json, only: [:create]

  def new
    @inquiry.build_from_gig_and_profile(gig, current_profile)

    # Gigmit::Matcher#matches? returns a boolean whether an aritst matches a given gig
    @is_matching = Gigmit::Matcher.new(gig, current_profile).matches?

    @profile = nil
    if current_profile.billing_address.blank? || current_profile.tax_rate.blank?
      @profile = current_profile

      if @profile.billing_address.blank?
        @profile.build_billing_address(name: "#{@profile.main_user.first_name} #{@profile.main_user.last_name}")
      end
    end

    Gigmit::Intercom::Event::ApplicationSawIncompleteBillingDataWarning.emit(gig.id, current_profile.id) unless current_profile.has_a_complete_billing_address?
    Gigmit::Intercom::Event::ApplicationSawIncompleteEpkWarning.emit(gig.id, current_profile.id) unless current_profile.epk_complete?
    Gigmit::Intercom::Event::ApplicationVisitedGigApplicationForm.emit(gig.id, current_profile.id) if current_profile.complete_for_inquiry?
  end

  def create
    if @inquiry.save_with_gig_and_profile(gig, current_profile)
      sync_riders(@inquiry, current_profile)

      Event::WatchlistArtistInquiry.emit(@inquiry.id)
      Gigmit::Intercom::Event::Simple.emit('gig-received-application', gig.promoter_id)
      IntercomCreateOrUpdateUserWorker.perform_async(gig.promoter_id)

      existing_gig_invite = current_profile.gig_invites.find_by(gig_id: params[:gig_id])
      if existing_gig_invite.present?
        Event::Read.emit(:gig_invite, existing_gig_invite.id)
      end

      render json: @inquiry, status: :created
    else
      render json: @inquiry.errors, status: :unprocessable_entity
    end
  end

  # only promoters use this
  def show
    # this redirect is for unfixed legacy links, because artist see inquiries
    # not prefixed with gig in the url
    redirect_to inquiry_path(@inquiry.id) and return if current_profile.artist?

    Event::Read.emit(:inquiry, @inquiry.id)
  end

  private

  def gig
    @gig ||= Gig.find_by! slug: params[:gig_id]
  end
  helper_method :gig

  def paywall_chroot
    if current_profile.artist? && flash[:bypass_trial_chroot] != true
      # subscribe to premium-trial first to be able to use the platform at all
      redirect_to '/ab/gigmit-pro-free-trial' and return
    end
  end

  def sync_riders(inquiry, profile)
    ['catering', 'technical'].each do |type|
      if current_profile.send("#{type}_rider").present?
        if current_profile.send("#{type}_rider").item_hash == params[:inquiry]["#{type}_rider_hash".to_sym]

          @inquiry.send("build_#{type}_rider", {user_id: current_user.id}).save!

          MediaItemWorker.perform_async(
            current_profile.send("#{type}_rider").id,
            @inquiry.send("#{type}_rider").id
          )
        end
      elsif @inquiry.send("#{type}_rider").present?
        
        current_profile.send("build_#{type}_rider", {user_id: current_user.id}).save!

        MediaItemWorker.perform_async(
          @inquiry.send("#{type}_rider").id, 
          current_profile.send("#{type}_rider").id
        )
      end
    end
  end
end
