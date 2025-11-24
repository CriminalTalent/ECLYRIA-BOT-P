#!/usr/bin/env ruby
# recalculate_house_scores.rb
# 기숙사 점수를 수동으로 재계산하는 스크립트

require 'dotenv/load'
require 'google/apis/sheets_v4'
require 'googleauth'

puts "=" * 60
puts "기숙사 점수 재계산 스크립트"
puts "=" * 60

# Google Sheets 서비스 초기화
begin
  sheets_service = Google::Apis::SheetsV4::SheetsService.new
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open('credentials.json'),
    scope: 'https://www.googleapis.com/auth/spreadsheets'
  )
  credentials.fetch_access_token!
  sheets_service.authorization = credentials
  
  puts "✓ Google Sheets 연결 성공"
rescue => e
  puts "✗ Google Sheets 연결 실패: #{e.message}"
  exit 1
end

sheet_id = ENV["GOOGLE_SHEET_ID"]

# 1단계: 사용자 시트에서 기숙사별 점수 집계
puts "\n[1단계] 사용자 시트에서 점수 집계 중..."

range = "'사용자'!A:K"
response = sheets_service.get_spreadsheet_values(sheet_id, range)
users = response.values || []

if users.empty?
  puts "✗ 사용자 시트가 비어있습니다."
  exit 1
end

headers = users[0]
house_idx = headers.index("기숙사")
score_idx = headers.index("개별 기숙사 점수")

if house_idx.nil? || score_idx.nil?
  puts "✗ '기숙사' 또는 '개별 기숙사 점수' 열을 찾을 수 없습니다."
  puts "현재 헤더: #{headers.inspect}"
  exit 1
end

puts "✓ 열 위치 확인: 기숙사=#{house_idx}, 점수=#{score_idx}"

# 기숙사별 합계 계산
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

puts "✓ 처리된 학생 수: #{user_count}"
puts "✓ 계산된 기숙사 점수:"
house_scores.each do |house, score|
  puts "  - #{house}: #{score}점"
end

# 2단계: 기숙사 시트 업데이트
puts "\n[2단계] 기숙사 시트 업데이트 중..."

range = "'기숙사'!A:B"
response = sheets_service.get_spreadsheet_values(sheet_id, range)
houses = response.values || []

if houses.empty?
  puts "✗ 기숙사 시트가 비어있습니다."
  exit 1
end

updated_count = 0
houses.each_with_index do |row, i|
  next if i == 0  # 헤더 스킵
  
  house_name = row[0].to_s.strip
  next if house_name.empty?
  
  total_score = house_scores[house_name] || 0
  
  # 업데이트
  cell_range = "'기숙사'!B#{i + 1}"
  value_range = Google::Apis::SheetsV4::ValueRange.new(values: [[total_score]])
  sheets_service.update_spreadsheet_value(
    sheet_id,
    cell_range,
    value_range,
    value_input_option: 'USER_ENTERED'
  )
  
  puts "  ✓ #{house_name}: #{total_score}점 업데이트"
  updated_count += 1
end

puts "\n" + "=" * 60
puts "재계산 완료!"
puts "=" * 60
puts "- 처리된 학생: #{user_count}명"
puts "- 업데이트된 기숙사: #{updated_count}개"
puts
puts "Google Sheets에서 결과를 확인하세요."
