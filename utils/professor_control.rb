# /root/mastodon_bots/professor_bot/utils/professor_control.rb
def auto_push_enabled?(sheet_manager, feature_name)
  sheet = sheet_manager.get_sheet("교수")
  values = sheet_manager.get_values("교수!A1:C2")
  headers = values[0]
  statuses = values[1]

  headers.each_with_index do |header, idx|
    next if header.nil?
    if header.strip == feature_name
      cell_value = statuses[idx]
      # true/false (체크박스) 또는 ON/OFF(문자열) 모두 허용
      return cell_value == true || cell_value.to_s.strip.upcase == "ON"
    end
  end

  false
rescue => e
  puts "[에러] auto_push_enabled? 확인 중 문제 발생: #{e.message}"
  false
end
