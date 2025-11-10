# /root/mastodon_bots/professor_bot/commands/homework_command.rb
require 'date'
require_relative '../utils/house_score_updater'
require_relative '../utils/professor_control'

class HomeworkCommand
  include HouseScoreUpdater

  def initialize(sheet_manager, mastodon_client, sender, status)
    @sheet_manager   = sheet_manager
    @mastodon_client = mastodon_client
    @acct_full       = sender            # 멘션용 (원격 도메인까지 그대로)
    @sender          = sender.split('@').first # 시트 조회용 (아이디만)
    @status          = status
  end

  def execute
    # 1) 학생 등록 여부 확인
    user = @sheet_manager.find_user(@sender)
    unless user
      return professor_reply("아직 학적부에 이름이 없군요. [입학/이름]으로 먼저 등록해주세요.")
    end

    today = Date.today.to_s

    # 2) 과제 중복 제출 확인 (시트에 해당 컬럼이 있을 때만 유효)
    if user[:homework_date] == today
      return professor_reply("오늘은 이미 과제를 제출했어요. 하루 한 번만 가능합니다.")
    end

    # 3) 과제 제출 처리
    @sheet_manager.increment_user_value(@sender, "갈레온", 5)
    @sheet_manager.increment_user_value(@sender, "기숙사점수", 3)
    @sheet_manager.set_user_value(@sender, "과제날짜", today)

    # 4) 기숙사 점수 갱신
    update_house_scores(@sheet_manager)

    # 5) 교수님식 피드백
    user_name = user[:name] || @sender
    message = <<~MSG
      훌륭해요, #{user_name} 학생.
      과제를 성실히 마쳤군요. 보상으로 5갈레온, 기숙사 점수 +3을 드립니다.
    MSG

    professor_reply(message.strip)
  rescue => e
    puts "[에러] HomeworkCommand 처리 중 예외 발생: #{e.message}"
    puts e.backtrace.first(5)
    professor_reply("음... 과제 제출 처리 중 문제가 생긴 것 같아요. 잠시 후 다시 시도해보세요.")
  end

  private

  def professor_reply(message)
    toot_id = @status.respond_to?(:id) ? @status.id : @status['id']
    # ✅ mastodon_client.reply(acct, message, in_reply_to_id: …)
    MastodonClient.client.reply(@acct_full, message, in_reply_to_id: toot_id)
  end
end
