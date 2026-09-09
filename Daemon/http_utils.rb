   
module HTTPUtils
	require 'rest-client'
	require 'net/http'
	require 'net/http/digest_auth'

	# Virtuoso's write endpoints (SPARQL Update, Graph Store Protocol) require real
	# HTTP Digest authentication and reject Basic auth outright (401, no retry) --
	# confirmed live against a Virtuoso 07.20 instance. rest-client (used by the
	# other methods in this module) has no Digest support, so this method exists
	# purely for that write path: probe for the WWW-Authenticate challenge, compute
	# the digest response via net-http-digest_auth, and resend.
	#
	# The probe request must NOT carry the real payload: Virtuoso rejects the
	# unauthenticated request and closes the connection as soon as it reads the
	# headers, without waiting to read the body. For any payload large enough that
	# writing it doesn't finish before that rejection arrives, the client gets an
	# ECONNRESET mid-write instead of the expected 401 -- confirmed live with a
	# ~550KB body. A tiny throwaway body sidesteps this entirely.
	def self.put_digest(url, content_type, payload, user, pass)
		uri = URI(url)
		uri.user = user
		uri.password = pass
		digest_auth = Net::HTTP::DigestAuth.new
		http = Net::HTTP.new(uri.host, uri.port)

		challenge_req = Net::HTTP::Put.new(uri)
		challenge_req['Content-Type'] = content_type
		challenge_req.body = ''
		challenge = http.request(challenge_req)
		unless challenge.code == '401'
			return challenge
		end

		auth_header = digest_auth.auth_header(uri, challenge['www-authenticate'], 'PUT')
		req = Net::HTTP::Put.new(uri)
		req['Authorization'] = auth_header
		req['Content-Type'] = content_type
		req.body = payload
		http.request(req)
	end

	def self.get(url, headers = {accept: "*/*"}, user = "", pass="")  # username and password go into headers as user: xxx and password: yyy
		
		
		begin
			request = RestClient::Request.new({
					method: :get,
					url: url.to_s,
					user: user,
					password: pass,
					headers: headers})
#$stderr.puts "GET request headers:", request.headers
response = request.execute()
			return response
		rescue RestClient::ExceptionWithResponse => e
			$stderr.puts e.response
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		rescue RestClient::Exception => e
			$stderr.puts e.response
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		rescue Exception => e
			$stderr.puts e
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		end		  # you can capture the Exception and do something useful with it!\n",
	end


	def self.post(url, headers = {accept: "*/*"}, payload = "", user = "", pass="")  # username and password go into headers as user: xxx and password: yyy

		begin
			response = RestClient::Request.execute({
				method: :post,
				url: url.to_s,
				user: user,
				password: pass,
				payload: payload,
				headers: headers
			})
$stderr.puts "POST request headers:", response.request.headers
			return response
		rescue RestClient::ExceptionWithResponse => e
			$stderr.puts e.response
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		rescue RestClient::Exception => e
			$stderr.puts e.response
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		rescue Exception => e
			$stderr.puts e
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		end		  # you can capture the Exception and do something useful with it!\n",
	end
	
	def self.put(url, headers = {accept: "*/*"}, payload = "", user = "", pass="")  # username and password go into headers as user: xxx and password: yyy

	  
		begin
			response = RestClient::Request.execute({
				method: :put,
				url: url.to_s,
				user: user,
				password: pass,
				payload: payload,
				headers: headers
			})
$stderr.puts "PUT request headers:", response.request.headers
			return response
		rescue RestClient::ExceptionWithResponse => e
			$stderr.puts e.response
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		rescue RestClient::Exception => e
			$stderr.puts e.response
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		rescue Exception => e
			$stderr.puts e
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		end		  # you can capture the Exception and do something useful with it!\n",
	end



	def self.delete(url, headers = {accept: "*/*"}, user = "", pass="") 
	  
		begin
			response = RestClient::Request.execute({
				method: :delete,
				url: url.to_s,
				user: user,
				password: pass,
				headers: headers
			})
$stderr.puts "DELETE request headers:", response.request.headers
			return response
		rescue RestClient::ExceptionWithResponse => e
			$stderr.puts e.response
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		rescue RestClient::Exception => e
			$stderr.puts e.response
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		rescue Exception => e
			$stderr.puts e
			response = false
			return response  # now we are returning 'False', and we will check that with an \"if\" statement in our main code
		end		  # you can capture the Exception and do something useful with it!\n",
	end


	def self.patchttl(body)
		# this will reorder the turtle so that all prefix lines are at the top
		# this is NOT the right thing to do (since prefixes are allowed to be redefined)
		# however, the turtle parser pukes on out-of-order @prefix lines
		# so... given that almost nobody ever redefines a prefix, this solves most problems...
		prefixes = Array.new
		bodylines = Array.new
		body.split("\n").each {|l| prefixes.concat([l]) if l =~ /^\@prefix/i; bodylines.concat([l]) unless l =~ /^\@prefix/i}
		reintegrated = Array.new
		reintegrated.concat([prefixes, bodylines])
		fixedbody = reintegrated.join("\n")
		return fixedbody
	end
end

