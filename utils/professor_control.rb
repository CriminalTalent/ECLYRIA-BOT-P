def auto_push_enabled?(sheet_manager, feature_name)
  values = sheet_manager.read_values("교수!A:D")
  return false if values.nil? || values.empty?
  
  # 헤더 행 (1행)
  headers = values[0]
  return false unless headers
  
  # 기능명 컬럼 찾기
  feature_index = nil
  
  case feature_name
  when "출석기능"
    feature_index = headers.index("야간출석자동통톨") || 0
  when "통금알림"
    feature_index = headers.index("통금알람") || 1
  when "통금해제알림"
    feature_index = headers.index("통금해제알람") || 2
  end
  
  return false unless feature_index
  
  # 2행의 체크박스 값 확인
  if values.length > 1 && values[1][feature_index]
    checkbox_value = values[1][feature_index].to_s.upcase
    return ["TRUE", "O", "YES", "Y", "ON"].include?(checkbox_value)
  end
  
  false
end
