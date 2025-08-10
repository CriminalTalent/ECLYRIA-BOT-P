# commands/attendance_command.rb
require_relative '../professor_control'
require_relative '../house_score_updater'
require 'date'

class AttendanceCommand
  def initialize(sheet_manager, mastodon_client, sender)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender
  end

  def execute
    # 1. 사용자 불러오기
    user = @sheet_manager.find_user(@sender)
    return reply("아직 학적부에 없는 학생입니다. [입학/이름]으로 등록해주세요.") if user.nil?

    # 2. 교수 시트에서 출석 기능 확인
    unless auto_push_enabled?(@sheet_manager, "출석기능")
      return reply("현재 출석 기능은 비활성화되어 있습니다.")
    end

    today = Date.today.to_s
    current_time = Time.now

    # 3. 출석 중복 확인
    if user[:attendance_date] == today
      return reply("오늘은 이미 출석하셨습니다.")
    end

    # 4. 출석 가능 시간 확인 (22:00 이전)
    if current_time.hour >= 22
      return reply("출석 마감 시간(22:00)을 지났습니다.")
    end

    # 5. 출석 처리
    @sheet_manager.increment_user_value(@sender, "갈레온", 2)
    @sheet_manager.increment_user_value(@sender, "개별 기숙사 점수", 1)
    @sheet_manager.set_user_value(@sender, "출석날짜", today)

    # 6. 기숙사 점수 반영
    update_house_scores(@sheet_manager)

    # 7. 순수 출석 확인 메시지만 (날씨 제거)
    user_name = user[:name] || @sender
    message = "#{user_name}학생의 출석이 확인되었습니다. 2갈레온, 기숙사 점수 1점을 추가하겠습니다."
    reply(message)
  end

  private

  def reply(message)
    @mastodon_client.reply(@sender, message)
  end
end
