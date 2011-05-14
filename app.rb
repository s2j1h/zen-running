# -*- coding: utf-8 -*-
require 'rubygems'
require 'data_mapper'
require 'sinatra'
require 'koala'
require 'rack-flash'
require 'sinatra/redirect_with_flash'
require 'haml'


enable :sessions

configure :development do
  DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/development.db")
end

configure :production do
	require 'newrelic_rpm'
   DataMapper.setup(:default, ENV['DATABASE_URL'])
end

set :root, File.dirname(__FILE__)
set :sessions, true
set :app_id, ENV['app_id'] # in dev mode: export app_id=xxx
set :app_secret, ENV['app_secret'] # in dev mode: app_secret=xxx
set :app_url, ENV['app_url'] ||  "http://localhost:4567"


use Rack::Flash, :sweep => true


class Hommage
  include DataMapper::Resource  
  property :id,                   Serial
  property :id_user,              String
  property :date,                 String
  property :duree,                String
  property :distance,             String
  property :commentaires,         Text
end


DataMapper.auto_upgrade!
#DataMapper.auto_migrate! #si changement de schéma à faire apparaître en production
DataMapper::Model.raise_on_save_failure = false #permet de savoir si tout est bien sauvegardé, à utiliser avec rescue


helpers do

  def oauth
    app_id         =  settings.app_id
    app_secret     =  settings.app_secret
    app_url        =  settings.app_url
    
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
 
