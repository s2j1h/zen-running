require 'rubygems'
require 'sinatra'
 
configure :production do
require 'newrelic_rpm'
end
 
# Quick test
get '/' do
"Hello from the ratpac
