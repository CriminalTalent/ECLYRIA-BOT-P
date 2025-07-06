# professor_auto_tasks.rb
require_relative 'mastodon_client'
require 'google_drive'
require 'time'

module ProfessorAutoTasks
  PROFESSOR_SHEET = '교수'

  def self.run_auto_tasks(client, sheet)
    session = GoogleDrive::Session.from_config(ENV['GOOGLE_CREDENTIALS_PATH'])
    ws = sheet.worksheet_by_title(PROFESSOR_SHEET)

    now_time = Time.now.strftime('%H:%M')

    (2..ws.num_rows).each do |row|
      active = ws[row, 1].strip == 'TRUE' || ws[row, 1].include?('✓') || ws[row, 1].include?('☑')
      task_time = ws[row, 2].strip
      task_type = ws[row, 3].strip

      next unless active && task_time == now_time

      case task_type
      when '아침 출석 자동툿'
        weather, note = ProfessorParser.random_weather_and_note
        message = "좋은 아침입니다, 여러분.\n오늘 날씨는 '#{weather}'이고요, #{note}\n출석 체크는 지금부터 가능합니다. 10시 전에 꼭 해주세요."
        client.post(message)

      when '저녁 출석 마감 자동툿'
        client.post("밤 10시가 되어 출석 체크가 종료됩니다. 아직 못 하신 분은 내일 아침을 기다려주세요. 좋은 밤 보내세요.")

      when '새벽 통금 알람'
        client.post("⚠️ 새벽 2시입니다. 모든 학생은 기숙사로 돌아가야 합니다. 복도 순찰이 시작됩니다.")

      when '통금 해제 알람'
        client.post("⏰ 오전 6시입니다. 통금이 해제되었습니다. 모두 안전하고 따뜻한 하루 보내세요.")
      end
    end
  end
end
