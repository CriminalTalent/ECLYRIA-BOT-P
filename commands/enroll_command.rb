# commands/enroll_command.rb
require 'date'

class EnrollCommand
  INITIAL_GALLEON = 20

  def initialize(sheet_manager, mastodon_client, sender, name, status)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender.gsub('@', '')
    @name = name
    @status = status
  end

  def execute
    existing_user = @sheet_manager.find_user(@sender)
    if existing_user
      @mastodon_client.reply(@status, "#{@name}학생은 이미 입학했어요.")
      return
    end

    user_row = [
      @sender,
      @name,
      INITIAL_GALLEON,
      "",
      "",
      ""
    ]
    @sheet_manager.append_values("사용자!A:F", [user_row])
    puts "[입학] 사용자 탭에 추가: #{@sender} (#{@name})"

    stat_row = [@sender, @name]
    @sheet_manager.append_values("스탯!A:B", [stat_row])
    puts "[입학] 스탯 탭에 ID/이름만 추가: #{@sender} (#{@name})"

    @mastodon_client.reply(@status, "#{@name}학생, 입학을 환영해요. 여기 학교 생활에 필요한 갈레온 20을 드릴게요.")
  end
end
