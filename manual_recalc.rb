#!/usr/bin/env ruby
# manual_recalc.rb

require 'bundler/setup'
Bundler.require

require_relative 'sheet_manager'
require_relative 'utils/house_score_updater'

puts "=" * 60
puts "House Score Recalculation"
puts "=" * 60

# Google Sheets service init
begin
  sheets_service = Google::Apis::SheetsV4::SheetsService.new
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open('credentials.json'),
    scope: 'https://www.googleapis.com/auth/spreadsheets'
  )
  credentials.fetch_access_token!
  sheets_service.authorization = credentials
  
  puts "Google Sheets connected"
rescue => e
  puts "Connection failed: #{e.message}"
  exit 1
end

# SheetManager init
sheet_manager = SheetManager.new(sheets_service, ENV["GOOGLE_SHEET_ID"])

puts "SheetManager initialized"
puts

# Update house scores
puts "Recalculating house scores..."
puts "-" * 60

HouseScoreUpdater.update_house_scores(sheet_manager)

puts "-" * 60
puts "\nComplete!"
puts "\nCheck the house sheet in Google Sheets."
