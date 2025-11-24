# commands/homework_command.rb
require 'date'
require_relative '../utils/house_score_updater'
require_relative '../utils/professor_control'

class HomeworkCommand
  include HouseScoreUpdater

  def initialize(sheet_manager, mastodon_client, sender, status)
    @sheet_manager   = sheet_manager
    @mastodon_client = mastodon_client
    @sender          = sender.gsub('@', '')  # 시트 조회용
    @status          = status
  end

  def execute
    # 1. 학생 등록 여부 확인
    user = @sheet_manager.find_user(@sender)
    unless user
      return professor_reply("아직 학적부에 이름이 없군요. [입학/이름]으로 먼저 등록해주세요.")
    end

    today = Date.today.to_s

    # 2. 과제 중복 제출 확인
    # 주의: sheet_manager의 find_user가 homework_date를 반환하지 않으므로
    # 직접 시트에서 읽어야 함
    homework_date = get_user_homework_date(@sender)
    if homework_date == today
      return professor_reply("오늘은 이미 과제를 제출했어요. 하루 한 번만 가능합니다.")
    end

    # 3. 과제 제출 처리
    @sheet_manager.increment_user_value(@sender, "갈레온", 5)
    @sheet_manager.increment_user_value(@sender, "개별 기숙사 점수", 3)  # 수정: 정확한 열 이름
    
    # 과제날짜 필드가 시트에 있다면 업데이트
    set_homework_date(@sender, today)

    puts "[과제] #{@sender} 과제 제출 완료 - 갈레온 +5, 기숙사 점수 +3"

    # 4. 기숙사 점수 갱신
    update_house_scores(@sheet_manager)

    # 5. 교수님식 피드백
    user_name = user[:name] || @sender
    message = "훌륭해요, #{user_name} 학생.\n과제를 성실히 마쳤군요. 보상으로 5갈레온, 기숙사 점수 +3을 드립니다."
    professor_reply(message)

  rescue => e
    puts "[에러] HomeworkCommand 처리 중 예외 발생: #{e.message}"
    puts e.backtrace.first(5)
    professor_reply("음... 과제 제출 처리 중 문제가 생긴 것 같아요. 잠시 후 다시 시도해보세요.")
  end

  private

  def professor_reply(message)
    @mastodon_client.reply(message, @status['id'])
  end

  # 사용자 시트에서 과제날짜 열 읽기 (L열 또는 커스텀 열)
  def get_user_homework_date(user_id)
    data = @sheet_manager.read('사용자', 'A:Z')
    return nil if data.empty?

    header = data[0] || []
    homework_col = header.index('과제날짜')
    return nil unless homework_col

    username_col = header.index('아이디') || 0

    data.each_with_index do |row, i|
      next if i.zero?
      if row[username_col].to_s.strip == user_id.strip
        return row[homework_col].to_s
      end
    end
    nil
  rescue => e
    puts "[에러] get_user_homework_date 실패: #{e.message}"
    nil
  end

  # 사용자 시트에 과제날짜 기록 (있다면)
  def set_homework_date(user_id, date)
    data = @sheet_manager.read('사용자', 'A:Z')
    return if data.empty?

    header = data[0] || []
    homework_col = header.index('과제날짜')
    return unless homework_col  # 과제날짜 열이 없으면 스킵

    username_col = header.index('아이디') || 0

    data.each_with_index do |row, i|
      next if i.zero?
      if row[username_col].to_s.strip == user_id.strip
        col_letter = @sheet_manager.col_idx_to_a1(homework_col)
        cell_range = @sheet_manager.a1_range('사용자', "#{col_letter}#{i + 1}")
        @sheet_manager.write_range(cell_range, [[date]])
        puts "[과제] #{user_id}의 과제날짜 = #{date}"
        return
      end
    end
  rescue => e
    puts "[에러] set_homework_date 실패: #{e.message}"
  end
end
