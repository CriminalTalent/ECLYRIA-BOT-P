# commands/homework_command.rb

require 'date'
require_relative '../house_score_updater'

class HomeworkCommand
  def initialize(sheet, client, user_id)
    @sheet = sheet
    @client = client
    @user_id = user_id
  end

  def execute
    user_sheet = @sheet.worksheet_by_title("사용자")
    house_sheet = @sheet.worksheet_by_title("기숙사점수")
    user_row = find_user_row(user_sheet, @user_id)

    unless user_row
      @client.reply(@user_id, "먼저 [입학/이름]으로 등록해주세요.")
      return
    end

    today = Date.today.to_s
    last_homework_day = user_row[10]&.strip

    if last_homework_day == today
      @client.reply(@user_id, "오늘은 이미 과제를 제출하셨습니다.")
      return
    end

    # 갈레온 +5
    user_row[2] = user_row[2].to_i + 5

    # 점수 +3
    user_row[10] = user_row[10].to_i + 3

    # 과제 제출일 갱신
    user_row[11] = today

    user_sheet.save

    # 기숙사 점수 갱신
    house_name = user_row[6]&.strip
    update_house_score(house_sheet, house_name, 3) if house_name && !house_name.empty?

    @client.reply(@user_id, "과제 제출 확인 하였습니다. 5갈레온과 기숙사 점수 3점을 지급하겠습니다. 수고하셨어요.")
  end

  private

  def find_user_row(sheet, id)
    (2..sheet.num_rows).each do |row_index|
      return sheet.rows[row_index - 1] if sheet[row_index, 1] == id
    end
    nil
  end

  def update_house_score(sheet, house_name, point)
    (2..sheet.num_rows).each do |row|
      if sheet[row, 1] == house_name
        sheet[row, 2] = sheet[row, 2].to_i + point
        sheet.save
        break
      end
    end
  end
end

