# commands/homework_command.rb
require 'date'

class HomeworkCommand
  def initialize(sheet_manager, mastodon_client, sender)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender.gsub('@', '')  # @domain 제거
  end

  def execute
    # 1. 사용자 확인
    user = @sheet_manager.find_user(@sender)
    unless user
      reply("아직 명부에 이름이 없구나. [입학/이름]으로 먼저 등록하고 오렴.")
      return
    end

    # 2. 과제 제출 처리 (무제한)
    # 갈레온 +5
    current_galleons = user[:galleons] || 0
    new_galleons = current_galleons + 5
    @sheet_manager.update_user(@sender, { galleons: new_galleons })
    
    # 3. 기숙사 점수 +3 (기숙사가 있을 경우)
    if user[:house] && !user[:house].empty?
      update_house_score(user[:house], 3)
    end

    # 4. 응답 메시지
    user_name = user[:name] || @sender
    message = "#{user_name}학생, 과제를 잘 해왔구나. 정말 기특하단다. 갈레온 5개를 주마."
    if user[:house] && !user[:house].empty?
      message += " #{user[:house]} 기숙사에도 3점을 더해주마. 훌륭하구나."
    end
    
    reply(message)
    puts "[과제] #{@sender} (#{user_name}) - 갈레온: #{current_galleons} → #{new_galleons}"
  end

  private

  def reply(message)
    @mastodon_client.reply(@sender, message)
  end

  def update_house_score(house_name, points)
    # 기숙사 탭에서 해당 기숙사 찾기
    values = @sheet_manager.read_values("기숙사!A:B")
    return if values.nil? || values.empty?
    
    values.each_with_index do |row, index|
      next if index == 0  # 헤더 스킵
      if row[0] == house_name
        current_score = (row[1] || 0).to_i
        new_score = current_score + points
        row_num = index + 1
        @sheet_manager.update_values("기숙사!B#{row_num}", [[new_score]])
        puts "[기숙사] #{house_name}: #{current_score} → #{new_score}"
        break
      end
    end
  end
end
