# -*- coding: utf-8 -*-
require 'rubygems'
require 'data_mapper'
require 'sinatra'
require 'koala'
require 'rack-flash'
require 'sinatra/redirect_with_flash'
require 'haml'
require 'date'

enable :sessions


configure :development do
  DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/development.db")
end

configure :production do
	require 'newrelic_rpm'
   DataMapper.setup(:default, ENV['DATABASE_URL'])
end

set :root, File.dirname(__FILE__)
set :views, "#{File.dirname(__FILE__)}/views"
set :public, "#{File.dirname(__FILE__)}/public"
set :sessions, true
set :app_id, ENV['app_id'].to_s # in dev mode: export app_id=xxx
set :app_secret, ENV['app_secret'].to_s # in dev mode: app_secret=xxx
set :app_url, ENV['app_url'].to_s
set :offset, 4

use Rack::Flash, :sweep => true


class Run
  include DataMapper::Resource  
  property :id,                   Serial
  property :id_user,              String
  property :date,                 Date
  property :duree,                Float
  property :distance,             Float
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
    redirect '/', :error =>  'Vous devez être connecté pour accéder à cette page'

  end

  def link_to text, url
    "<a href='#{ URI.encode url }'>#{ text }</a>"
  end 

  def moisFR id
    mois = ["JAN","FEV","MARS","AVRIL","MAI","JUIN","JUIL","AOUT","SEPT","OCT","NOV","DEC"]
    mois[id-1]
  end

  def formatKM km
    if km == 0
      return "-"
    else
      return km
    end
  end

  def formatDuree duree
    dureeH = duree.to_int
    dureeM = ((duree-dureeH)*60).to_int
    dureeS = ((((duree-dureeH)*60)-dureeM)*60).to_int
    if dureeH < 10
      dureeH = "0" << dureeH.to_s
    else
      dureeH = dureeH.to_s
    end
    if dureeM == 60
      dureeM = "00"
    elsif dureeM < 10
      dureeM = "0" << dureeM.to_s
    else
      dureeM = dureeM.to_s
    end
    if dureeS == 60
      dureeS = "00"
    elsif dureeS < 10
      dureeS = "0" << dureeS.to_s
    else
      dureeS = dureeS.to_s
    end

    return dureeH,dureeM,dureeS
  end

end

before '/run/*' do
  authorize! unless logged_in?
end

get '/' do
  redirect '/pages/0'
end

get '/pages/:offset' do
  if params[:offset] == ""
    @offset = 0
  else
    @offset =  Integer(params[:offset])
  end

  if logged_in?
    id_user = facebook_graph(:get_object, 'me')['id']
    @runs = Run.all(:id_user => id_user, :limit => settings.offset, :offset => @offset*settings.offset, :order => [ :date.desc ])
    if Run.all(:id_user => id_user).count < (@offset+1)*settings.offset+1
      @end = "True"
    else
      @end = "False"  
    end

  end
  haml :index
end

post '/' do
  redirect '/'
end

get '/friends' do
  redirect '/friends/pages/0'
end

get '/friends/pages/:offset' do
  if params[:offset] == ""
    @offset = 0
  else
    @offset =  Integer(params[:offset])
  end

  if logged_in?
    friendsFF = facebook_graph(:get_object, 'me/friends')['data']
    listFriends = []
    @friendsName = {}
    friendsFF.each do |friend|
      listFriends << friend['id']
      @friendsName[friend['id']] = friend["name"]
    end
    @runs = Run.all(:id_user => listFriends, :limit => settings.offset, :offset => @offset*settings.offset, :order => [ :date.desc ])
    @friendsPic = {}
    @runs.each do |run|
      if @friendsPic[run.id_user] == nil
        @friendsPic[run.id_user] = facebook_graph(:get_picture, run.id_user)
      end
    end
    if Run.all(:id_user => listFriends).count < (@offset+1)*settings.offset+1
      @end = "True"
    else
      @end = "False"
    end
    
    haml :friends
  else
    redirect '/'
  end

end

get '/run/add' do
  if logged_in?
    haml :add
  else
    redirect '/'
  end
end

post '/run/add' do
  if logged_in?

    if params[:date] == "" || params[:dureeM] == "" || params[:dureeS] == ""
      redirect '/run/add', :error =>  "Merci de remplir l'ensemble des informations obligatoires" 
    end

    date = params[:date]
    dureeH = params[:dureeH]
    dureeM = params[:dureeM]
    dureeS = params[:dureeS]
    distance = params[:distance]
    commentaires = params[:commentaires]
    begin
      if dureeH == "" 
        dureeH = 0
      else
        dureeH = Integer(dureeH)
      end
      dureeM = Integer(dureeM)
      dureeS = Integer(dureeS)
      if dureeH<0 || dureeH> 24 || dureeM <0 || dureeM >= 60 || dureeS <0 || dureeS >= 60
        redirect '/run/add', :error =>  "Durée incorrecte, merci de respecter le format heure, minutes, secondes"
      end
      duree = 1*dureeH + dureeM/60.0 + dureeS/3600.0
    rescue
      redirect '/run/add', :error =>  "Durée incorrecte, merci de respecter le format heure, minutes, secondes"
    end
    #parse distance
    begin
      if distance == "" 
        distance = 0
      else
        distance = Float(distance)
      end
      if distance < 0
        redirect '/run/add', :error =>  "Distance incorrecte, merci d'entrer une valeur en km, ex: 10.4"
      end
    rescue
      redirect '/run/add', :error =>  "Distance incorrecte, merci d'entrer une valeur en km, ex: 10.4"
    end
    
    #rajouter l'id facebook
    id_user = facebook_graph(:get_object, 'me')['id']

    run = Run.create(
      :id_user => id_user,
      :date => date, 
      :duree => duree, 
      :distance => distance, 
      :commentaires => commentaires 
    )
    if run.save
       redirect '/', :notice => "Une nouvelle course a été créée"
    else
      puts run.errors.inspect
      redirect '/', :error => "Une erreur a empêché la sauvegarde de la course - merci de contacter votre admin préféré"
    end
  else
    redirect '/'
  end

end


get '/oauth' do
  if params[:code]
    begin
      access_token = oauth.get_access_token(params[:code])
      session[:facebook_access_token] = access_token
      flash[:notice] = "Vous êtes connecté sur Zen-runnin', bienvenue !"
    rescue Koala::Facebook::APIError
      flash[:error] = "Désolé, nous ne pouvons vous connecter - merci de réessayer ultérieurement ou de contacter votre admin préféré si le problème persiste"
    end
  end
  redirect '/'
end

get '/logout' do
  session.delete :facebook_access_token
  redirect '/', :notice =>  'Vous êtes déconnecté'

end

post 'deauthorize' do
  puts 'lost a user :('  
end
 
