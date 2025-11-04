# /root/mastodon_bots/professor_bot/utils/house_score_updater.rb

module HouseScoreUpdater
  # 기존 메서드 (개별 기숙사 점수 업데이트)
  def self.update_score(house_sheet, house_name, points)
    return if house_name.nil? || house_name.strip.empty?
    house_name = house_name.strip

    (2..house_sheet.num_rows).each do |row|
      if house_sheet[row, 1].strip == house_name
        current_score = house_sheet[row, 2].to_i
        house_sheet[row, 2] = current_score + points
        house_sheet.save
        puts "[기숙사 점수] #{house_name} → +#{points}점 (총합: #{house_sheet[row, 2]})"
        break
      end
    end
  end

  # AttendanceCommand 호환용 래퍼 메서드
  def update_house_scores(sheet_manager)
    begin
      house_sheet = sheet_manager.get_sheet("기숙사점수")
      users = sheet_manager.get_values("사용자!A2:K") || []

      users.each do |row|
        name, house, score = row[0], row[4], row[10]
        next if house.nil? || score.nil?
        HouseScoreUpdater.update_score(house_sheet, house, score.to_i)
      end

      puts "[DEBUG] 기숙사 점수 일괄 업데이트 완료"
    rescue => e
      puts "[에러] update_house_scores 실패: #{e.message}"
    end
  end
end
