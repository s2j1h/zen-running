require 'rubygems'
require 'sinatra'
require 'omniauth/oauth'

enable :sessions

#Here you have to put your own Application ID and Secret
APP_ID = "822050aa6886db8e663cbb1f9b1c63d3"
APP_SECRET = "ab8aa063c069e6a6f5a10c2f5c5ccf13"

 
configure :production do
	require 'newrelic_rpm'
end
 
use OmniAuth::Builder do
  provider :facebook, APP_ID, APP_SECRET, { :scope => 'email, status_update, publish_stream' }
end

get '/' do
    @articles = []
    @articles << {:title => 'Deploying Rack-based apps in Heroku', :url => 'http://docs.heroku.com/rack'}
    @articles << {:title => 'Learn Ruby in twenty minutes', :url => 'http://www.ruby-lang.org/en/documentation/quickstart/'}

    erb :index
end

get '/auth/facebook/callback' do
  session['fb_auth'] = request.env['omniauth.auth']
  session['fb_token'] = session['fb_auth']['credentials']['token']
  session['fb_error'] = nil
  redirect '/'
end

get '/auth/failure' do
  clear_session
  session['fb_error'] = 'In order to use this site you must allow us access to your Facebook data<br />'
  redirect '/'
end

get '/logout' do
  clear_session
  redirect '/'
end

def clear_session
  session['fb_auth'] = nil
  session['fb_token'] = nil
  session['fb_error'] = nil
end

get 'signout' do
  puts 'lost a customer :('
end
