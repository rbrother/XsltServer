@REM programs/saxon.net has the commercial schema-avare version that we need
set SAXON_HOME=c:\programs\saxon
ir -d -D -X:NoAdaptiveCompilation -Ic:/programs/saxon/bin xslt_server.rb %*
