# main.rb (Professor Bot - 완전 수정판)
require 'bundler/setup'
require 'dotenv'
require 'time'
require 'json'
require 'ostruct'
require 'google/apis/sheets_v4'
require 'googleauth'
require 'net/http'
require 'rufus-scheduler'
require_relative 'mastodon_client'
require_relative 'sheet_manager'
require_relative 'professor_command_parser'
require_relative 'cron_tasks/morning_attendance_push'
require_relative 'cron_tasks/evening_attendance_end'
require_relative 'cron_tasks/curfew_alert'
require_relative 'cron_tasks/curfew_release'
require_relative 'cron_tasks/midnight_reset'

Dotenv.load('.env')

# 환경 변수 검증
required_envs = %w[MASTODON_DOMAIN ACCESS_TOKEN SHEET_ID GOOGLE_CREDENTIALS_PATH]
missing = required_envs.select { |v| ENV[v].nil? || ENV[v].strip.empty? }
if missing.any?
  missing.each { |v| puts "[환경변수 누락] #{v}" }
  puts "[오류] .env 파일을 확인해주세요."
  exit 1
end

DOMAIN       = ENV['MASTODON_DOMAIN']
TOKEN        = ENV['ACCESS_TOKEN']
SHEET_ID     = ENV['SHEET_ID']
CRED_PATH    = ENV['GOOGLE_CREDENTIALS_PATH']
LAST_ID_FILE = 'last_mention_id.txt'

MENTION_ENDPOINT = "https://#{DOMAIN}/api/v1/notifications"
POST_ENDPOINT    = "https://#{DOMAIN}/api/v1/statuses"

puts "[교수봇] 실행 시작 (#{Time.now.strftime('%H:%M:%S')})"

# Google Sheets 연결
begin
  creds = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open(CRED_PATH),
    scope: ['https://www.googleapis.com/auth/spreadsheets']
  )
  creds.fetch_access_token!
  service = Google::Apis::SheetsV4::SheetsService.new
  service.authorization = creds
  sheet_manager = SheetManager.new(service, SHEET_ID)
  puts "[Google Sheets] 연결 성공"
rescue ArgumentError
  creds = Google::Auth::ServiceAccountCredentials.make_creds({json_key_io: File.open(CRED_PATH), scope: ['https://www.googleapis.com/auth/spreadsheets']})
  creds.fetch_access_token!
  service = Google::Apis::SheetsV4::SheetsService.new
  service.authorization = creds
  sheet_manager = SheetManager.new(service, SHEET_ID)
  puts "[Google Sheets] 연결 성공 (대체 방식)"
rescue => e
  puts "[에러] Google Sheets 연결 실패: #{e.message}"
  exit 1
end

# 마스토돈 클라이언트 (스케줄러용)
mastodon = MastodonClient.new(
  base_url: "https://#{DOMAIN}",
  token: TOKEN
)

# 스케줄러 시작
scheduler = Rufus::Scheduler.new

# 매일 아침 9:00 - 출석 시작 안내
scheduler.cron '0 9 * * *' do
  puts "[스케줄러] 아침 9시 출석 안내 실행"
  run_morning_attendance_push(sheet_manager, mastodon)
end

# 매일 밤 22:00 - 출석 마감 안내
scheduler.cron '0 22 * * *' do
  puts "[스케줄러] 밤 10시 출석 마감 안내 실행"
  run_evening_attendance_end(sheet_manager, mastodon)
end

# 매일 새벽 2:00 - 통금 알림
scheduler.cron '0 2 * * *' do
  puts "[스케줄러] 새벽 2시 통금 알림 실행"
  run_curfew_alert(sheet_manager, mastodon)
end

# 매일 아침 6:00 - 통금 해제 안내
scheduler.cron '0 6 * * *' do
  puts "[스케줄러] 아침 6시 통금 해제 안내 실행"
  run_curfew_release(sheet_manager, mastodon)
end

# 매일 자정 00:00 - 베팅 횟수 및 체력 초기화
scheduler.cron '0 0 * * *' do
  puts "[스케줄러] 자정 초기화 실행"
  run_midnight_reset(sheet_manager, mastodon)
end

puts "[스케줄러] 시작됨 (9시 출석, 22시 마감, 2시 통금, 6시 해제, 0시 초기화)"

# Mentions API 처리 함수
def fetch_mentions(since_id = nil)
  url = "#{MENTION_ENDPOINT}?types[]=mention&limit=20"
  url += "&since_id=#{since_id}" if since_id
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  [JSON.parse(res.body), res.each_header.to_h]
rescue => e
  puts "[에러] 멘션 불러오기 실패: #{e.message}"
  [[], {}]
end

REPLY = proc do |content, in_reply_to_id|
  # 인자 순서 자동 수정
  if in_reply_to_id.is_a?(String) && !in_reply_to_id.match?(/^\d+$/) &&
     content.is_a?(String) && content.match?(/^\d+$/)
    puts "[REPLY GUARD] 인자 순서가 뒤집혀 있어 교정합니다."
    content, in_reply_to_id = in_reply_to_id, content
  end

  uri = URI(POST_ENDPOINT)
  req = Net::HTTP::Post.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req.set_form_data(
    'status' => content,
    'in_reply_to_id' => in_reply_to_id,
    'visibility' => 'unlisted'
  )

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

  puts "[REPLY] code=#{res.code} to=#{in_reply_to_id}"
  if res.code.to_i >= 300
    puts "[에러] 답글 전송 실패 (HTTP #{res.code})"
  else
    puts "[REPLY OK] toot posted"
  end
rescue => e
  puts "[에러] 답글 전송 예외: #{e.class} - #{e.message}"
end

# Mentions 감시 루프
last_checked_id = File.exist?(LAST_ID_FILE) ? File.read(LAST_ID_FILE).strip : nil
base_interval = 60
cooldown_on_429 = 300
loop_count = 0

puts "[MENTION] 감시 시작..."

loop do
  begin
    loop_count += 1
    delay = base_interval + rand(-10..10)
    puts "[루프 #{loop_count}] Mentions 확인 (지연 #{delay}s)"
    mentions, headers = fetch_mentions(last_checked_id)

    if headers['x-ratelimit-remaining'] && headers['x-ratelimit-remaining'].to_i < 1
      reset_after = headers['x-ratelimit-reset'] ? headers['x-ratelimit-reset'].to_i : cooldown_on_429
      puts "[경고] Rate limit 도달 → #{reset_after}초 대기"
      sleep(reset_after)
      next
    end

    mentions.sort_by! { |m| m['id'].to_i }
    mentions.each do |mention|
      next unless mention['type'] == 'mention'
      next unless mention['status']

      status = mention['status']
      sender = mention['account']['acct']
      content = status['content'].gsub(/<[^>]*>/, '').strip
      toot_id = status['id']

      puts "[MENTION] @#{sender}: #{content}"
      begin
        mention['status']  = OpenStruct.new(status)
        mention['account'] = OpenStruct.new(mention['account'])
        ProfessorParser.parse(REPLY, sheet_manager, mention)
      rescue => e
        puts "[에러] 명령어 실행 실패: #{e.message}"
      end

      last_checked_id = mention['id']
      File.write(LAST_ID_FILE, last_checked_id)
    end

  rescue => e
    if e.message.include?('429')
      puts "[경고] 429 Too Many Requests → 5분 대기"
      sleep(cooldown_on_429)
    else
      puts "[에러] Mentions 루프 오류: #{e.class} - #{e.message}"
      sleep(30)
    end
  end

  sleep(base_interval + rand(-10..10))
end
