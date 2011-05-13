# -*- coding: utf-8 -*-
require 'rubygems'
require 'sinatra'
require 'koala'
require 'rack-flash'
require 'haml'

enable :sessions

configure :production do
	require 'newrelic_rpm'
end

set :root, File.dirname(__FILE__)
set :sessions, true

use Rack::Flash

helpers do

  def oauth
    app_id         =  "822050aa6886db8e663cbb1f9b1c63d3"
    app_secret     =  "ab8aa063c069e6a6f5a10c2f5c5ccf13"
    app_url        =  "http://localhost:4567"
    
    callback_url = "#{ app_url }/oauth"
    @oauth ||= Koala::Facebook::OAuth.new app_id, app_secret, callback_url
  end

  def logged_in?
    session.has_key? :facebook_access_token
  end

  def facebook_graph method_name, *args
    begin
      return {} unless logged_in?
      Koala::Facebook::GraphAPI.new( session[:facebook_access_token] ).send method_name, *args
    rescue Koala::Facebook::APIError
      authorize!
    end
  end

  def authorize!
    session.delete :facebook_access_token
    flash[:error] = 'You devez être connecté pour accéder à cette page'
    redirect '/'
  end

  def link_to text, url
    "<a href='#{ URI.encode url }'>#{ text }</a>"
  end 
end

before '/shared_interests/*' do
  authorize! unless logged_in?
end

get '/' do
  if logged_in?
    @friends = facebook_graph(:get_object, 'me/friends')['data']
  end

  haml :index
end

post '/' do
  redirect '/'
end

get '/oauth' do
  if params[:code]
    begin
      access_token = oauth.get_access_token(params[:code])
      session[:facebook_access_token] = access_token
      flash[:notice] = "Vous êtes connecté sur Zen-runnin', Bienvenue !"
    rescue Koala::Facebook::APIError
      flash[:error] = "Désolé, nous ne pouvons vous connecter - merci de réessayer ultérieurement"
    end
  end
  redirect '/'
end

get '/logout' do
  session.delete :facebook_access_token
  flash[:notice] = 'Vous êtes déconnecté'
  redirect '/'
end

post 'deauthorize' do
  puts 'lost a user :('  
end
 
