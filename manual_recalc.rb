#!/usr/bin/env ruby
# manual_recalc.rb - Direct API version

require 'bundler/setup'
Bundler.require

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

sheet_id = ENV["GOOGLE_SHEET_ID"]

# Step 1: Read user data
puts "\n[Step 1] Reading user sheet..."

begin
  response = sheets_service.get_spreadsheet_values(sheet_id, "사용자!A:K")
  users = response.values || []
rescue => e
  puts "Error reading sheet: #{e.message}"
  exit 1
end

if users.empty?
  puts "User sheet is empty"
  exit 1
end

headers = users[0]
puts "Headers: #{headers.inspect}"

house_idx = headers.index("기숙사")
score_idx = headers.index("개별 기숙사 점수")

if house_idx.nil? || score_idx.nil?
  puts "Error: Cannot find '기숙사' or '개별 기숙사 점수' column"
  puts "Available headers: #{headers.inspect}"
  exit 1
end

puts "Found columns - House: #{house_idx}, Score: #{score_idx}"

# Step 2: Calculate house totals
puts "\n[Step 2] Calculating house totals..."

house_scores = Hash.new(0)
user_count = 0

users[1..].each do |row|
  next if row.nil? || row.empty?
  
  house = row[house_idx].to_s.strip
  score = (row[score_idx] || 0).to_i
  
  next if house.empty?
  
  house_scores[house] += score
  user_count += 1
end

puts "Processed #{user_count} students"
puts "House totals:"
house_scores.each do |house, score|
  puts "  #{house}: #{score}"
end

# Step 3: Update house sheet
puts "\n[Step 3] Updating house sheet..."

begin
  response = sheets_service.get_spreadsheet_values(sheet_id, "기숙사!A:B")
  houses = response.values || []
rescue => e
  puts "Error reading house sheet: #{e.message}"
  exit 1
end

if houses.empty?
  puts "House sheet is empty"
  exit 1
end

updated_count = 0
houses.each_with_index do |row, i|
  next if i == 0  # Skip header
  
  house_name = row[0].to_s.strip
  next if house_name.empty?
  
  total_score = house_scores[house_name] || 0
  
  # Update cell
  cell_range = "기숙사!B#{i + 1}"
  value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[total_score]])
  
  begin
    sheets_service.update_spreadsheet_value(
      sheet_id,
      cell_range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
    puts "  #{house_name}: #{total_score} points updated"
    updated_count += 1
  rescue => e
    puts "  Error updating #{house_name}: #{e.message}"
  end
end

puts "\n" + "=" * 60
puts "Complete!"
puts "=" * 60
puts "Processed students: #{user_count}"
puts "Updated houses: #{updated_count}"
puts "\nCheck Google Sheets for results."
