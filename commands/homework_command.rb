# commands/homework_command.rb
require 'date'
require_relative '../house_score_updater'

class HomeworkCommand
  def initialize(sheet_manager, mastodon_client, sender)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender
  end

  def execute
    # 1. 사용자 확인
    user = @sheet_manager.find_user(@sender)
    unless user
      @mastodon_client.reply(@sender, "먼저 [입학/이름]으로 등록해주세요.")
      return
    end

    today = Date.today.to_s
    
    # 2. 과제 중복 확인 (last_bet_date 필드를 과제날짜로 임시 사용)
    if user[:last_bet_date] == today
      @mastodon_client.reply(@sender, "오늘은 이미 과제를 제출하셨습니다.")
      return
    end

    # 3. 과제 제출 처리
    @sheet_manager.increment_user_value(@sender, "갈레온", 5)
    @sheet_manager.increment_user_value(@sender, "개별 기숙사 점수", 3)
    @sheet_manager.set_user_value(@sender, "과제날짜", today)

    # 4. 기숙사 점수 갱신
    update_house_scores(@sheet_manager)

    @mastodon_client.reply(@sender, "과제 제출 확인 하였습니다. 5갈레온과 기숙사 점수 3점을 지급하겠습니다. 수고하셨어요.")
  end
end
