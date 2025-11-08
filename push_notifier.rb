# /root/mastodon_bots/professor_bot/push_notifier.rb

module PushNotifier
  # 공용 메시지 발송 메서드
  # mastodon_client: MastodonClient 인스턴스
  # message: 발송할 문자열
  def self.broadcast(mastodon_client, message)
    return if message.nil? || message.strip.empty?

    begin
      # MastodonClient 클래스에 post_status 메서드가 있다고 가정
      if mastodon_client.respond_to?(:post_status)
        mastodon_client.post_status(message)
      else
        # 직접 POST 요청 수행 (fallback)
        uri = URI("#{mastodon_client.base_url}/api/v1/statuses")
        req = Net::HTTP::Post.new(uri)
        req['Authorization'] = "Bearer #{mastodon_client.token}"
        req.set_form_data('status' => message, 'visibility' => 'unlisted')

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(req)
        end
      end

      puts "[PushNotifier] 전송 성공: #{message[0..40]}..."
    rescue => e
      puts "[PushNotifier] 전송 실패: #{e.message}"
    end
  end
end
