# utils/house_score_updater.rb
module HouseScoreUpdater
  module_function

  def update_house_scores(sheet_manager)
    puts "[기숙사 점수] 갱신 시작"
    
    begin
      # 1단계: 사용자 시트에서 개별 기숙사 점수 집계
      user_range = "사용자!A:K"
      user_values = sheet_manager.read_values(user_range)
      
      if user_values.nil? || user_values.empty?
        puts "[경고] 사용자 시트가 비어있습니다."
        return
      end

      house_totals = Hash.new(0)
      
      user_values[1..].each do |row|
        next if row.nil? || row[0].nil?
        
        house = (row[5] || "").to_s.strip
        individual_score = (row[10] || 0).to_i
        
        # 날짜 형식이거나 빈 값은 제외
        next if house.empty? || house =~ /^\d{4}-\d{2}-\d{2}$/
        
        house_totals[house] += individual_score
      end

      puts "[기숙사 점수] 집계 완료: #{house_totals.inspect}"

      # 2단계: 기숙사 시트 읽기
      house_range = "기숙사!A:B"
      house_values = sheet_manager.read_values(house_range)
      
      if house_values.nil? || house_values.empty?
        puts "[경고] 기숙사 시트가 비어있습니다."
        return
      end

      # 3단계: 기숙사 시트 업데이트
      house_values[1..].each_with_index do |row, idx|
        next if row.nil? || row[0].nil?
        
        house_name = row[0].to_s.strip
        new_score = house_totals[house_name] || 0
        row_num = idx + 2
        
        range = "기숙사!B#{row_num}"
        sheet_manager.update_values(range, [[new_score]])
        
        puts "[기숙사 점수] #{house_name}: #{new_score}점 반영"
      end

      puts "[기숙사 점수] 갱신 완료"
      
    rescue => e
      puts "[오류] 기숙사 점수 갱신 실패: #{e.message}"
      puts e.backtrace.first(3)
    end
  end

  # 기존 호환성을 위한 메서드
  def update_score(house_sheet, house_name, points)
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
