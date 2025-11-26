# commands/attendance_command.rb
require_relative '../utils/professor_control'
require_relative '../utils/house_score_updater'
require 'date'

class AttendanceCommand
  def initialize(sheet_manager, mastodon_client, sender, status)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender.gsub('@', '')
    @status = status
  end

  def execute
    # 1. 학생 정보 확인
    user = @sheet_manager.find_user(@sender)
    return professor_reply("아직 학적부에 없는 학생이군요. [입학/이름]으로 등록을 마쳐주세요.") if user.nil?

    # 2. 출석 기능 상태 확인
    unless ProfessorControl.auto_push_enabled?(@sheet_manager, "아침출석자동툿")
      return professor_reply("지금은 출석 기능이 잠시 중단된 상태예요. 나중에 다시 시도해보세요.")
    end

    today = Date.today.to_s
    current_time = Time.now

    # 3. 중복 출석 방지
    if user[:attendance_date] == today
      return professor_reply("오늘은 이미 출석을 완료했어요. 성실하군요, 훌륭합니다.")
    end

    # 4. 출석 가능 시간 확인 (22시 이전)
    if current_time.hour >= 22
      return professor_reply("출석 마감 시간(22:00)이 지나버렸군요. 내일은 조금 더 일찍 오도록 해요.")
    end

    # 5. 출석 처리
    @sheet_manager.increment_user_value(@sender, "갈레온", 2)
    @sheet_manager.increment_user_value(@sender, "개별 기숙사 점수", 1)
    @sheet_manager.set_user_value(@sender, "출석날짜", today)

    puts "[출석] #{@sender} 출석 완료 - 갈레온 +2, 기숙사 점수 +1"

    # 6. 기숙사 점수 반영
    @sheet_manager.sync_house_system if @sheet_manager.respond_to?(:sync_house_system)

    # 7. 교수님식 출석 멘트
    user_name = user[:name] || @sender
    message = "좋아요, #{user_name} 학생. 오늘도 성실히 출석했군요.\n(보상: 2갈레온, 기숙사 점수 +1)"
    professor_reply(message)

  rescue => e
    puts "[에러] AttendanceCommand 처리 중 예외 발생: #{e.message}"
    puts "[에러] 상세: #{e.class}"
    puts e.backtrace.first(10)
    professor_reply("음… 잠시 오류가 생긴 것 같아요. 잠시 후 다시 시도해보세요.")
  end

  private

  def professor_reply(message)
    @mastodon_client.reply(message, @status['id'])
  end

  def get_user_attendance_date(user_id)
    data = @sheet_manager.read('사용자', 'A:I')
    header = data[0]
    attendance_col = header.index("출석날짜")
    return nil unless attendance_col

    data[1..].each do |row|
      next if row.nil? || row[0].nil?
      if row[0].to_s.strip == user_id
        return row[attendance_col].to_s.strip
      end
    end
    nil
  end
end
