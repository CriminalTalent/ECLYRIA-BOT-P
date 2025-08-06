# commands/attendance_command.rb

require_relative '../professor_control'
require_relative '../utils/weather_message'
require_relative '../house_score_updater'
require 'date'

class AttendanceCommand
  def initialize(sheet_manager, mastodon_client, user_id, user_name)
    @sheet_manager = sheet_manager
    @client = mastodon_client
    @user_id = user_id
    @user_name = user_name
  end

  def execute
    # 1. 사용자 불러오기
    user = @sheet_manager.find_user(@user_id)
    return reply("등록되지 않은 사용자입니다. [입학/이름]으로 등록해주세요.") if user.nil?

    # 2. 교수 시트에서 출석 기능 확인
    unless auto_push_enabled?(@sheet_manager, "출석기능")
      return reply("현재 출석 기능은 비활성화되어 있습니다.")
    end

    today = Date.today.to_s
    current_time = Time.now

    # 3. 출석 중복 확인
    if user["출석날짜"] == today
      return reply("오늘은 이미 출석하셨습니다.")
    end

    # 4. 출석 가능 시간 확인 (22:00 이전)
    if current_time.hour >= 22
      return reply("출석 마감 시간(22:00)을 지났습니다.")
    end

    # 5. 출석 처리
    @sheet_manager.increment_user_value(@user_id, "갈레온", 2)
    @sheet_manager.increment_user_value(@user_id, "개별 기숙사 점수", 1)
    @sheet_manager.set_user_value(@user_id, "출석날짜", today)

    # 6. 기숙사 점수 반영
    update_house_scores(@sheet_manager)

    # 7. 날씨 조언 포함 메시지 구성
    message = "✅ #{@user_name}님의 출석이 확인되었습니다. +2갈레온, +1점이 지급되었습니다."

    if auto_push_enabled?(@sheet_manager, "출석 날씨 자동알림")
      weather = random_weather_message_with_style
      message = "#{weather[:text]}\n\n#{message}"
    end

    # 8. 마스토돈 푸시 전송
    reply(message)
  end

  private

  def reply(message)
    @client.reply(@user_id, message)
  end
end
