# commands/homework_command.rb
require 'date'
require_relative '../utils/house_score_updater'

class HomeworkCommand
  def initialize(sheet_manager, mastodon_client, sender, status)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender.gsub('@', '')
    @status = status
  end

  def execute
    # 1. 사용자 확인
    user = @sheet_manager.find_user(@sender)
    unless user
      return reply("먼저 [입학/이름]으로 등록해주세요.")
    end

    today = Date.today.to_s

    # 2. 과제 중복 확인
    if user[:last_bet_date] == today
      return reply("오늘은 이미 과제를 제출하셨습니다.")
    end

    # 3. 과제 제출 처리
    @sheet_manager.increment_user_value(@sender, "갈레온", 5)
    @sheet_manager.increment_user_value(@sender, "개별 기숙사 점수", 3)
    @sheet_manager.set_user_value(@sender, "과제날짜", today)

    # 4. 기숙사 점수 갱신
    update_house_scores(@sheet_manager)

    reply("과제 제출 확인 하였습니다. 5갈레온과 기숙사 점수 3점을 지급하겠습니다. 수고하셨어요.")
  end

  private

  def reply(message)
    @mastodon_client.reply(@status, message)
  end
end
