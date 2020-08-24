# app/models/inquiry.rb

class Inquiry < ActiveRecord::Base
  include Gigmit::Concern::Negotiation
  include Gigmit::Concern::Riders

  # ...

  def build_from_gig_and_profile(initial_gig, initial_profile)
    self.gig                   = initial_gig
    self.deal_possible_fee_min = initial_gig.deal_possible_fee_min
    self.artist_contact        = initial_profile.last_inquired(:artist_contact)
    self.travel_party_count    = initial_profile.last_inquired(:travel_party_count)
    self.custom_fields         = initial_gig.custom_fields

    if initial_gig.fixed_fee_option && initial_gig.fixed_fee_max == 0
      self.fixed_fee = 0
    end

    if gig.fixed_fee_negotiable
      self.gig.fixed_fee_option = true
      self.gig.fixed_fee_max    = 0
    end

    # set this rider here for new
    # if user keeps it until create, they will be copied async
    # otherwise he can pseudo delete the riders in the Inquiry#new form and
    # add new ones
    self.technical_rider = initial_profile.technical_rider
    self.catering_rider  = initial_profile.catering_rider
  end
end
