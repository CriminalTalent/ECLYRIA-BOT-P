# /root/mastodon_bots/professor_bot/scheduler.rb
require 'rufus-scheduler'
require 'dotenv/load'

require_relative './mastodon_client'
require_relative './sheet_manager'

require_relative './cron_tasks/morning_attendance_push'
require_relative './cron_tasks/evening_attendance_end'
require_relative './cron_tasks/curfew_alert'
require_relative './cron_tasks/curfew_release'

# ----------------------------------------------
# 마스토돈 + 시트 클라이언트 초기화
# ----------------------------------------------
begin
  mastodon = MastodonClient.new(
    base_url: ENV['MASTODON_BASE_URL'],
    token: ENV['MASTODON_TOKEN']
  )
  sheet_manager = SheetManager.new(ENV['GOOGLE_SHEET_ID'])
  puts "[교수봇 스케줄러] 클라이언트 초기화 완료"
rescue => e
  puts "[에러] 클라이언트 초기화 실패: #{e.message}"
  exit 1
end

# ----------------------------------------------
# 스케줄러 시작
# ----------------------------------------------
scheduler = Rufus::Scheduler.new

# ✅ 예외 발생 시에도 개별 작업이 전체 스케줄러를 중단시키지 않도록 보호
def safe_task(name)
  yield
rescue => e
  puts "[에러][#{name}] #{e.class}: #{e.message}"
end

# 📌 매일 아침 7:00 - 출석 시작 안내
scheduler.cron '0 7 * * *' do
  safe_task('morning_attendance_push') do
    run_morning_attendance_push(sheet_manager, mastodon)
  end
end


# 📌 매일 새벽 2:00 - 통금 알림
scheduler.cron '0 2 * * *' do
  safe_task('curfew_alert') do
    run_curfew_alert(sheet_manager, mastodon)
  end
end

# 📌 매일 아침 6:00 - 통금 해제 안내
scheduler.cron '0 6 * * *' do
  safe_task('curfew_release') do
    run_curfew_release(sheet_manager, mastodon)
  end
end

puts "[교수봇 스케줄러] 실행 중... Ctrl+C 로 종료 가능"
scheduler.join
