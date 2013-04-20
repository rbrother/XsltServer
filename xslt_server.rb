# family database web application
require 'pathname'
require 'cgi'
require 'System.Xml, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089'
require 'saxon9pe-api.dll'
require 'ibex20.dll'

class Exception
    def to_verbose_s
        self.respond_to?(:ToString) ? ToString() : to_s()
    end
end

module Brotherus

    class XsltServer
        include System::Collections::Generic
        include System::Net
        include System::Net::Sockets
        include System::Web
        include System::Text
        include Saxon::Api
        
        PORT = 8081  # Select any free port you wish

        # The constructor which make the TcpListener start listening on the
        # given port. It also calls a Thread on the method StartListen(). 
        def initialize
            @listeners = []
            puts "XsltServer IronRuby 1.0 by Robert Brotherus"
            Dns.GetHostEntry( "localhost" ).AddressList.each do | addr |
                puts "localhost: #{addr}:#{PORT}"
                my_listener = TcpListener.new( addr, PORT )
                my_listener.Start()
                @listeners << my_listener
            end
            processor = Processor.new( true ) # schema aware processor to use the Saxon-PE (Professional) features
            @builder = processor.NewDocumentBuilder()
            @compiler = processor.NewXsltCompiler()

            # start listing on the given port
            puts "Web Server Running... Press ^C to Stop..."
            # start the thread which calls the method 'StartListen'
        end

        # This method Accepts new connection and
        # First it receives the welcome massage from the client,
        # Then it sends the Current date time to the Client.
        def start_listen
            get_and_process_request while true
        end
        
        def xslfo
            Object.const_get('xslfo')
        end
        
        def get_and_process_request
            get_pending_listener
            puts "\n\n================== Processing Request ================== 1.0"
            start = System::DateTime.Now
            myListener = get_pending_listener()
            my_socket = myListener.AcceptSocket()
            if my_socket.Connected
                puts "Client Connected: #{my_socket.RemoteEndPoint}"
                bReceive = System::Array.of(System::Byte).new(1024)
                i = my_socket.Receive( bReceive, bReceive.Length, 0 )
                request = Encoding.UTF8.GetString( bReceive )
                begin
                    process_request( request, my_socket )
                rescue Exception => ex
                    puts ex.to_verbose_s
                ensure
                    my_socket.Close()
                    duration = System::DateTime.Now - start
                    puts "Finished in #{duration.TotalSeconds} s"
                end
            end
        end

        def process_request( buffer, my_socket )
            lines = buffer.split('\n').map { |line| line.strip }
            
            puts "\nRequest raw lines:"
            puts lines

            # Example:
            # LINE: GET /XsltService?xmlFile=C%3A%5CInetpub%5Cwwwroot%5Cfamily%5Cxml%5CBrotherus.xml,xsltFile=C%3A%5CInetpub%5Cwwwroot%5Cfamily%5Cxslt%5CPersonList.xslt,baseURL=xxx,dataURL=yyy HTTP/1.1
            # LINE: Host: localhost:8081
            # LINE: User-Agent: Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.14) Gecko/20080404 Firefox/2.0.0.14
            # LINE: Accept: text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5
            # LINE: Accept-Language: en-us,en;q=0.5
            # LINE: Accept-Encoding: gzip,deflate
            # LINE: Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7
            # LINE: Keep-Alive: 300
            # LINE: Connection: keep-alive
            # LINE: Cookie: ASPSESSIONIDACASDQSR=EHFNFFFCBAELDHLBGIMJKOKM
            # LINE: Cache-Control: max-age=0

            # Wikipedia: The encoding Windows-1252 is a superset of ISO 8859-1, but differs 
            # from the IANA's ISO-8859-1 by using displayable characters rather than control 
            # characters in the 0x80 to 0x9F range. It is known to Windows by the code page 
            # number 1252, and by the IANA-approved name "windows-1252".

            raise "Not a proper GET request: #{lines.first}" unless lines.first =~ /GET (.+) HTTP\/(\w.\w)/
            http_version = $2 #  eg. "1.1"
            request = $1.gsub('\\', '/') # eg. /XsltService?xmlFile=C%3A%5CInetpub%5Cwwwroot%5Cfamily%5Cxml%5CBrotherus.xml,xsltFile=C%3A%5CInetpub%5Cwwwroot%5Cfamily%5Cxslt%5CPersonList.xslt,baseURL=xxx,dataURL=yyy
            par_dict = parse_parameters( request )

            xmlFile = par_dict["xmlFile"]
            xsltFile = par_dict["xsltFile"]
            raise "File not found: #{xmlFile}" unless File.exist?(xmlFile)
            raise "File not found: #{xsltFile}" unless File.exist?(xsltFile)
            result = ""
            if par_dict["application"] == "XsltService"
                result = transform(par_dict, xmlFile, xsltFile)
            elsif par_dict["application"] == "XslFO"
                xmlDir = Pathname.new(xmlFile).parent
                foFile = xmlDir + "report.fo"
                pdfFile = xmlDir + "report.pdf"
                File.delete(foFile) if File.exist?(foFile)
                File.delete(pdfFile) if File.exist?(pdfFile)
                result = transform(par_dict, xmlFile, xsltFile)
                System::IO::File.write_all_text(foFile.to_s, result)
                fo = xslfo::FODocument.new()
                fo.generate(foFile.to_s, pdfFile.to_s)
                result = "<h2>XSL FO DONE</h2>"
            end
            content = Encoding.GetEncoding("ISO-8859-1").GetBytes(result)
            send_header(http_version, "text/xml;charset=ISO-8859-1", content.Length, "200 OK", my_socket)
            send_to_browser(content, my_socket)
        rescue Exception => ex
            puts "Exception in processing request: #{ex.to_verbose_s}"
            errorMessage = "<p>" + ex.to_verbose_s.gsub('\n', "<br/>") + "</p>"
            send_header("1.0", "", errorMessage.Length, "404 Not Found", my_socket)
            send_to_browser(errorMessage, my_socket)
        end

        def parse_parameters( request )
            raise "/(XsltService|XslFO)? or / not found in request: #{request}" unless request =~ /^\/(XsltService|XslFO)\?(.+)$/
            par_dict = {}
            par_dict["application"] = $1
            pars = $2
            pars.split(/,/).each_with_index do | par, index |                
                puts("    #{index}: [#{par}]") rescue puts("decoder error in parameter #{index}")
                raise "Parameter key-value pair does not contain equal-sign: #{par}" unless par =~ /^(.+)=(.*)$/
                key = $1
                par_dict[key] = decode_par( $2 )
                puts "            -> #{par_dict[key]}"
            end
            raise "Compulsory parameter xmlFile or xsltFile missing" if (!par_dict.has_key?("xmlFile") || !par_dict.has_key?( "xsltFile" )) 
            par_dict
        end

        def decode_par( s )
            s = s.gsub( "%E4", "ä" ).gsub( "%F6", "ö" ).gsub( "%C4", "Ä" ).gsub( "%D6", "Ö" ).gsub("%FC","ü")
            CGI.unescape(s)
        end

        def transform( par_dict, xmlFile, xsltFile )
            transformer = @compiler.Compile( path_to_uri( xsltFile ) ).Load()
            xml = @builder.Build( path_to_uri( xmlFile ) )
            transformer.InitialContextNode = xml
            sb = System::IO::StringWriter.new()
            settings = System::Xml::XmlWriterSettings.new()
            settings.OmitXmlDeclaration = true
            xmlWriter = System::Xml::XmlWriter.Create( sb, settings )
            par_dict.each_pair do | par_name, value |
                transformer.SetParameter( to_qname(par_name), to_atomic(value) )
            end
            transformer.Run( TextWriterDestination.new( xmlWriter ) )
            sb.ToString()
        end
        
        def to_qname(s)
            QName.new( System::Xml::XmlQualifiedName.method(:new).overload(System::String).call(s) )
        end
        
        def to_atomic(s)
            XdmAtomicValue.new(s.to_s.to_clr_string) # need explicit to_clr_string to aid overload resolution
        end

        def path_to_uri( filePath )
            System::Uri.new( "file:///" + filePath.gsub( /\\/, '/' ) )
        end

        # This function send the Header Information to the client (Browser)
        # shttp_version: HTTP Version
        # sMIMEHeader: Mime Type
        # iTotBytes: Total Bytes to be sent in the body
        # my_socket: Socket reference
        def send_header( shttp_version, sMIMEHeader, content_length, sStatusCode, my_socket )
            header = "HTTP/#{shttp_version} #{sStatusCode}\n" +
                "Content-Type: #{sMIMEHeader}\n" +
                "Accept-Ranges: bytes\n" +
                "Content-Length: #{content_length}\n\n"
                puts "sending header:\n#{header}"
                send_to_browser( header, my_socket )
        end

        # Overloaded Function, takes string, convert to bytes and calls 
        # overloaded sendToBrowserFunction.
        # data : The data to be sent to the browser(client)
        # my_socket: Socket reference
        def send_to_browser( data, my_socket )
            if data.is_a?(String)
                send_to_browser( Encoding.UTF8.GetBytes( data ), my_socket )
            else
                num_bytes = 0
                if my_socket.Connected
                    if ( num_bytes = my_socket.Send( data, data.Length, 0 ) ) == -1
                        puts "Socket Error cannot Send Packet"
                    else
                        puts "No. of bytes send #{num_bytes}"
                    end
                else
                    puts "Connection Dropped...."
                end
            end
        rescue Exception => e
            puts "Error Occurred : #{e} "
        end

        def get_pending_listener
            while true
                @listeners.each do | listener |
                    return listener if listener.Pending()
                end
                Thread.Sleep( 100 )
            end
        end

    end

end

if __FILE__ == $0
    begin
        Brotherus::XsltServer.new.start_listen
    rescue Exception => ex        
        puts ex.to_verbose_s
    end
end