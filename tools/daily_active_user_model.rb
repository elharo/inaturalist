# frozen_string_literal: true

##
#
# Daily Active User Model
#
##

# Patch SegmentationStatistic
class SegmentationStatistic < ApplicationRecord
  def self.generate_segmentation_data( start_date, end_date, use_database: false )
    segmentation_data = {}
    current_date = end_date
    num_days = ( end_date.to_date - start_date.to_date ).to_i
    num_days.times do
      puts "Processing #{current_date}..."
      users_from_kibana_data( current_date, segmentation_data )
      current_date -= 1.day
    end
    users_from_db( end_date, segmentation_data ) if use_database
    segmentation_data
  end
end

def fetch_data_from_api( url )
  uri = URI( url )
  response = Net::HTTP.get_response( uri )
  raise "Failed to fetch data from API" unless response.is_a?( Net::HTTPSuccess )

  JSON.parse( response.body )
rescue StandardError => e
  puts "Error fetching data from API: #{e.message}"
  {}
end

# Designate Day 0 (yesterday)
day_0 = Time.now.utc.end_of_day - 1.day

# Define the date sets
# Define date ranges for each case
date_ranges = [
  { d1: day_0 - 1.day, d2: day_0, use_db: true }, # Active 0
  { d1: day_0 - 2.days, d2: day_0 - 1.day, use_db: true }, # Active 1
  { d1: day_0 - 7.days, d2: day_0 - 2.days }, # Active 2-6
  { d1: day_0 - 8.days, d2: day_0 - 7.days }, # Active 7
  { d1: day_0 - 9.days, d2: day_0 - 8.days }, # Active 8
  { d1: day_0 - 30.days, d2: day_0 - 9.days }, # Active 9-29
  { d1: day_0 - 31.days, d2: day_0 - 30.days }, # Active 30
  { d1: day_0 - 32.days, d2: day_0 - 31.days } # Active 31
]

# Generate data for each case
active_data = date_ranges.map do | date_range |
  SegmentationStatistic.generate_segmentation_int( date_range[:d1], date_range[:d2], date_range[:use_db] )
end

# Extract required data for analysis
active_0, active_1, active_2_6, active_7, active_8, active_9_29, active_30, active_31 = active_data
active_0_new_users = active_0.select {| _, v | v[:created_at].zero? }.keys
active_1_new_users = active_1.select {| _, v | v[:created_at].zero? }.keys

# Extract required data for analysis
# Day 0
dau_0 = active_0.keys
current_users_d0 = dau_0 & ( active_1.keys | active_2_6.keys )
new_sensu_lato_d0 = dau_0 - ( active_1.keys | active_2_6.keys )
at_risk_waus_d0 = ( active_1.keys | active_2_6.keys ) - current_users_d0 - new_sensu_lato_d0
at_risk_maus_d0 = ( active_7.keys | active_8.keys | active_9_29.keys ) -
  at_risk_waus_d0 - current_users_d0 - new_sensu_lato_d0
new_users_d0 = new_sensu_lato_d0 & active_0_new_users
new_other_d0 = new_sensu_lato_d0 - new_users_d0

# Day 1
dau_1 = active_1.keys
current_users_d1 = dau_1 & ( active_2_6.keys | active_7.keys )
new_sensu_lato_d1 = dau_1 - ( active_2_6.keys | active_7.keys )
at_risk_waus_d1 = ( active_2_6.keys | active_7.keys ) - current_users_d1 - new_sensu_lato_d1
at_risk_maus_d1 = ( active_8.keys | active_9_29.keys | active_30.keys ) -
  at_risk_waus_d1 - current_users_d1 - new_sensu_lato_d1
new_users_d1 = new_sensu_lato_d1 & active_1_new_users
new_other_d1 = ( new_sensu_lato_d1 - new_users_d1 )

# Resurrected and reactivated
at_risk_maus_d2 = ( active_9_29.keys | active_30.keys | active_31.keys ) -
  ( active_2_6.keys | active_7.keys | active_8.keys )
reactivated_users_d0 = new_other_d0 & at_risk_maus_d1
resurrected_users_d0 = new_other_d0 - reactivated_users_d0
reactivated_users_d1 = new_other_d1 & at_risk_maus_d2
resurrected_users_d1 = new_other_d1 - reactivated_users_d1

# Dead users
url = "https://www.inaturalist.org/stats/summary.json"
response_data = fetch_data_from_api( url )
total_users = response_data["total_users"]
dead_users_d0 = total_users - current_users_d0.count - at_risk_waus_d0.count - at_risk_maus_d0.count -
  new_users_d0.count - reactivated_users_d0.count - resurrected_users_d0.count

# Calculate counts
curent_users = current_users_d0.count
at_risk_ways = at_risk_waus_d0.count
at_risk_maus = at_risk_maus_d0.count
new_users = new_users_d0.count
reactivated_users = reactivated_users_d0.count
resurrected_users = resurrected_users_d0.count
dead_users = dead_users_d0

# Calculate rates
nurr = ( current_users_d0 & new_users_d1 ).count / new_users_d1.count.to_f
surr = ( current_users_d0 & resurrected_users_d1 ).count / resurrected_users_d1.count.to_f
rurr = ( current_users_d0 & reactivated_users_d1 ).count / reactivated_users_d1.count.to_f
curr = ( current_users_d0 & current_users_d1 ).count / current_users_d1.count.to_f
iwaurr = ( current_users_d0 & at_risk_waus_d1 ).count / at_risk_waus_d1.count.to_f
wau = ( at_risk_maus_d0 & at_risk_waus_d1 ).count / at_risk_waus_d1.count.to_f
imaurr = ( reactivated_users_d0 & at_risk_maus_d1 ).count / at_risk_maus_d1.count.to_f
mau = ( at_risk_maus_d1 - at_risk_maus_d0 - reactivated_users_d0 ).count / at_risk_maus_d1.count.to_f
rr = resurrected_users_d0.count / dead_users_d0.to_f

data = {
  date: day_0,
  curent_users: curent_users,
  at_risk_ways: at_risk_ways,
  at_risk_maus: at_risk_maus,
  new_users: new_users,
  reactivated_users: reactivated_users,
  resurrected_users: resurrected_users,
  dead_users: dead_users,
  nurr: nurr,
  surr: surr,
  rurr: rurr,
  curr: curr,
  iwaurr: iwaurr,
  wau: wau,
  imaurr: imaurr,
  mau: mau,
  rr: rr
}

# Print the data
puts data.to_json
