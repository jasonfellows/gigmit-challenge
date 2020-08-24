# app/controllers/gigs/inquiries_controller.rb

class Gigs::InquiriesController < Gigs::ApplicationController
  load_and_authorize_resource # https://github.com/CanCanCommunity/cancancan#32-loaders

  respond_to :html, only: [:new, :show]
  respond_to :json, only: [:create]

  def new
    @inquiry.build_from_gig_and_profile(gig, current_profile)

    # Gigmit::Matcher#matches? returns a boolean whether an aritst matches a
    # given gig
    @is_matching = Gigmit::Matcher.new(gig, current_profile).matches?

    if current_profile.billing_address.blank? || current_profile.tax_rate.blank?
      @profile = current_profile
      if @profile.billing_address.blank?
        @profile.build_billing_address
        @profile.billing_address.name = [
          @profile.main_user.first_name,
          @profile.main_user.last_name
        ].join(' ')
      end
    end

    Gigmit::Intercom::Event::ApplicationSawIncompleteBillingDataWarning.emit(gig.id, current_profile.id) unless current_profile.has_a_complete_billing_address?
    Gigmit::Intercom::Event::ApplicationSawIncompleteEpkWarning.emit(gig.id, current_profile.id) unless current_profile.epk_complete?

    Gigmit::Intercom::Event::ApplicationVisitedGigApplicationForm.emit(gig.id, current_profile.id) if current_profile.complete_for_inquiry?
  end

  def create
    @inquiry.gig        = gig
    @inquiry.artist     = current_profile
    @inquiry.user       = current_profile.main_user
    @inquiry.promoter   = gig.promoter

    if @inquiry.save
      if current_profile.technical_rider.present? && current_profile.technical_rider.item_hash == params[:inquiry][:technical_rider_hash]
        @inquiry.build_technical_rider(user_id: current_user.id).save!
        MediaItemWorker.perform_async(current_profile.technical_rider.id, @inquiry.technical_rider.id)
      end

      if current_profile.catering_rider.present? && current_profile.catering_rider.item_hash == params[:inquiry][:catering_rider_hash]
        @inquiry.build_catering_rider(user_id: current_user.id).save!
        MediaItemWorker.perform_async(current_profile.catering_rider.id, @inquiry.catering_rider.id)
      end

      #if profile has no rides yet, which means, this is the profiles first inquiry ever
      #copy the riders from the inquiry to the profile
      if current_profile.technical_rider.blank? && @inquiry.technical_rider.present?
        current_profile.build_technical_rider(user_id: current_user.id).save!
        MediaItemWorker.perform_async(@inquiry.technical_rider.id, current_profile.technical_rider.id)
      end

      if current_profile.catering_rider.blank? && @inquiry.catering_rider.present?
        current_profile.build_catering_rider(user_id: current_user.id).save!
        MediaItemWorker.perform_async(@inquiry.catering_rider.id, current_profile.catering_rider.id)
      end

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

  #only promoter use this
  def show
    #this redirect is for unfixed legacy links, because artist see inquiries
    #not prefixed with gig in the url
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
end
