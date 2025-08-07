# commands/enroll_command.rb

require 'date'

class EnrollCommand
  def initialize(sheet_manager, mastodon_client, sender, name)
    @sheet_manager = sheet_manager
    @mastodon_client = mastodon_client
    @sender = sender
    @name = name
  end

  def execute
    user_sheet = @sheet.worksheet_by_title("사용자")
    existing_row = find_user_row(user_sheet, @user_id)

    if existing_row
      @client.reply(@user_id, "#{@name}님은 이미 입학하셨습니다.")
      return
    end

    new_row = [
      @user_id,       # A: 마스토돈 ID
      @name,          # B: 이름
      INITIAL_GALLEON,# C: 갈레온
      "",             # D: 아이템
      "",             # E: 메모
      "",             # F: 기숙사 (빈칸)
      "",             # G: 마지막베팅일
      "",             # H: 오늘베팅횟수
      "",             # I: 출석날짜
      "",             # J: 마지막타로일
      0               # K: 개별 기숙사 점수
    ]

    user_sheet.insert_rows(user_sheet.num_rows + 1, [new_row])
    user_sheet.save

    @client.reply(@user_id, "#{@name}님, 입학을 확인했습니다. 열차에 탑승해 주세요.")
  end

  private

  def find_user_row(sheet, id)
    (2..sheet.num_rows).each do |row|
      return row if sheet[row, 1] == id
    end
    nil
  end
end

