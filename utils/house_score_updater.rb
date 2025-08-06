# utils/house_score_updater.rb

module HouseScoreUpdater
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
end

