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
set :offset, 6

use Rack::Flash, :sweep => false


class Run
  include DataMapper::Resource  
  property :id,                   Serial
  property :id_user,              String
  property :date,                 Date
  property :duree,                Float
  property :distance,             Float
  property :commentaires,         Text
  property :id_post,              String
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

  def format_toKM km
    if km == 0
      return "-"
    else
      return km
    end
  end

  def get_funSentence km, dureeH, dureeM
    sentence_goodperf = [
                "a couru de toutes ses forces",
                "a tout donné",
                "était dans une forme éblouissante",
                "a sprinté et doublé tout le monde",
                "est sur le chemin du marathon",
                "est une bête de course!",
                "pourra bientôt faire le semi-marathon de Paris"
                ]
    sentence_badperf = [
                "était un peu fatigué(e)",
                "a fait de son mieux",
                "était en petite forme",
                "s'est fait doublé(e) par tout les autres coureurs"
                ]
    sentence_normalperf = [
                "a bien couru",
                "a fait son petit bonhomme de chemin",
                "est en progression permanente"
                ]
    if km>=20 || dureeH>0
      return sentence_goodperf[rand(sentence_goodperf.size)]
    elsif (km != 0 && km<2) || (dureeH == 0 && dureeM < 20)
      return sentence_badperf[rand(sentence_badperf.size)]
    else
      return sentence_normalperf[rand(sentence_normalperf.size)]
    end
  end

  def format_to_niceDate date
    now = Date.today
    puts now
    puts date
    mois = ["janvier","février","mars","avril","mai","juin","juillet","août","septembre","octobre","novembre","décembre"]
    if date.day == now.day && date.month == now.month && date.year == now.year
      return "Aujourd'hui"
    elsif date == now - 1
      return "Hier"
    else
      return "Le #{date.day} " + mois[date.month-1] +  " #{date.year}"
    end
  end

  def format_toDuree duree
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

before '/friends/*' do
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
    puts "#{settings.offset} offst=#{@offset*settings.offset}"
    @runs.each do |run|
      puts "BEFORE: #{run.id} #{run.date} #{run.distance} comment= #{run.commentaires}"
    end
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

get '/run/stats' do
  if logged_in?
    id_user = facebook_graph(:get_object, 'me')['id']
    runs = Run.all(:id_user => id_user,:order => [ :date.asc])
    run_first = Run.first(:id_user => id_user)
    @runDuree,@runDistance,@runVitesse = run_first, run_first, run_first
    @runStatsDistance,@runStatsDuree,@runStatsVitesse   = [], [],[]
    runs.each do |run|
      if run.duree > @runDuree.duree
        @runDuree = run
      end
      if run.distance > @runDistance.distance
        @runDistance = run
      end
      if run.distance/run.duree > @runVitesse.distance/@runVitesse.duree
        @runVitesse = run
      end
    @runStatsDistance << [run.date.strftime("%s").to_i*1000,run.distance]
    @runStatsDuree << [run.date.strftime("%s").to_i*1000,run.duree]
    @runStatsVitesse << [run.date.strftime("%s").to_i*1000,run.distance/run.duree]
    end
    haml :stats
  else
    redirect '/'
  end

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

    if params[:date] == "" || params[:dureeM] == ""
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
      if dureeS == ""
        dureeS = 0
      else
        dureeS = Integer(dureeS)
      end
      dureeM = Integer(dureeM)
      dureeS = Integer(dureeS)
      if dureeH<0 || dureeH> 24 || dureeM <0 || dureeM >= 60 || dureeS <0 || dureeS >= 60
        redirect '/run/add', :error =>  "Durée incorrecte, merci de respecter le format heure, minutes, secondes"
      end
      if dureeH == 0 && dureeM == 0 && dureeS == 0
        redirect '/run/add', :error =>  "Merci de rentrer une durée supérieure à 0"
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
    
    #créer la phrase pour le post
    duree_sentence = ""
    if dureeH > 0
      duree_sentence = "#{dureeH} heure"
      if dureeH > 1
         duree_sentence << "s"
      end
      if dureeM>0
        duree_sentence << " et "
      end
    end
    if dureeM>0
      duree_sentence << "#{dureeM} minute"
      if dureeM>1
        duree_sentence << "s"
      end
    end
    sentence = "a couru pendant #{duree_sentence}"
    if distance > 0
      sentence << " sur #{distance}km"
    end
    if commentaires != ""
      sentence << ": #{commentaires}"
    end
    id_post = facebook_graph(:put_wall_post,sentence)['id']


    run = Run.create(
      :id_user => id_user,
      :date => date, 
      :duree => duree, 
      :distance => distance, 
      :commentaires => commentaires,
      :id_post => id_post
    )
    if run.save
      puts "sauvegarde OK"
      redirect '/', :notice => "Une nouvelle course a été créée"
    else
      puts run.errors.inspect
      facebook_graph(:delete_object, id_post)
      redirect '/', :error => "Une erreur a empêché la sauvegarde de la course - merci de contacter votre admin préféré"
    end
  else
    redirect '/'
  end

end


get '/oauth' do
  if params[:code]
    puts params[:code]
    begin
      access_token = oauth.get_access_token(params[:code], {:ca_file => "/usr/lib/ssl/certs/ca-certificates.crt"})
      session[:facebook_access_token] = access_token
      flash[:notice] = "Vous êtes connecté sur ZenRunnin', bienvenue !"
      puts "OK/JR: I'm IN"
    rescue Koala::Facebook::APIError => bang
      puts "ERROR/JR: impossible de se connecter à facebook: #{bang}"
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
 
