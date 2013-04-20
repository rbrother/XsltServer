@REM programs/saxon.net has the commercial schema-avare version that we need
echo NOTE: SAXON_HOME environment variable needed for this program
ir -I"%SAXON_HOME%/bin" xslt_server.rb %*
