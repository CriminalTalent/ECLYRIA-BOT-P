#!/usr/bin/env ruby
# manual_recalc.rb
# sheet_manager를 사용한 기숙사 점수 재계산

require 'bundler/setup'
Bundler.require

require_relative 'sheet_manager'
require_relative 'utils/house_score_updater'

puts "=" * 60
puts "기숙사 점수 수동 재계산"
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
  puts "✗ 연결 실패: #{e.message}"
  exit 1
end

# SheetManager 초기화 (실제 교수봇과 동일한 방식)
sheet_manager = SheetManager.new(sheets_service, ENV["GOOGLE_SHEET_ID"])

puts "✓ SheetManager 초기화 완료"
puts

# 기숙사 점수 업데이트 실행
puts "기숙사 점수 재계산 시작..."
puts "-" * 60

HouseScoreUpdater.update_house_scores(sheet_manager)

puts "-" * 60
puts "\n재계산 완료!"
puts "\nGoogle Sheets에서 '기숙사' 시트를 확인하세요."
