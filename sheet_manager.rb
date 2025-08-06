# sheet_manager.rb

require 'google_drive'

class SheetManager
  def initialize(sheet_key)
    @session = GoogleDrive::Session.from_config(ENV['GOOGLE_CREDENTIALS_PATH'])
    @spreadsheet = @session.spreadsheet_by_key(sheet_key)
  end

  # 시트 이름으로 시트 객체 반환
  def worksheet_by_title(title)
    @spreadsheet.worksheet_by_title(title)
  end

  # 시트 이름 목록 반환
  def sheet_titles
    @spreadsheet.worksheets.map(&:title)
  end

  # 예: 사용자 시트 가져오기
  def users_sheet
    worksheet_by_title('사용자')
  end

  # 예: 교수 시트 가져오기
  def professor_sheet
    worksheet_by_title('교수')
  end

  # 예: 기숙사 시트 가져오기
  def house_sheet
    worksheet_by_title('기숙사')
  end

  # 필요하면 아이템 등 추가 가능
end

