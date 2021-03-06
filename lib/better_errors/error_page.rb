require "cgi"
require "json"
require "securerandom"

module BetterErrors
  # @private
  class ErrorPage
    def self.template_path(template_name)
      File.expand_path("../templates/#{template_name}.erb", __FILE__)
    end

    def self.template(template_name)
      Erubi::Engine.new(File.read(template_path(template_name)), escape: true)
    end

    attr_reader :exception, :env, :repls

    def initialize(exception, env)
      @exception = RaisedException.new(exception)
      @env = env
      @start_time = Time.now.to_f
      @repls = []
    end

    def id
      @id ||= SecureRandom.hex(8)
    end

    def render(template_name = "main")
      binding.eval(self.class.template(template_name).src)
    end

    def do_variables(opts)
      index = opts["index"].to_i
      @frame = backtrace_frames[index]
      @var_start_time = Time.now.to_f
      { html: render("variable_info") }
    end

    def do_eval(opts)
      index = opts["index"].to_i
      code = opts["source"]

      unless (binding = backtrace_frames[index].frame_binding)
        return { error: "REPL unavailable in this stack frame" }
      end

      @repls[index] ||= REPL.provider.new(binding, exception)

      eval_and_respond(index, code)
    end

    def backtrace_frames
      exception.backtrace
    end

    def exception_type
      exception.type
    end

    def exception_message
      exception.message.lstrip
    end

    def application_frames
      backtrace_frames.select(&:application?)
    end

    def first_frame
      application_frames.first || backtrace_frames.first
    end

  private
    def editor_url(frame)
      BetterErrors.editor[frame.filename, frame.line]
    end

    def rack_session
      env['rack.session']
    end

    def rails_params
      env['action_dispatch.request.parameters']
    end

    def uri_prefix
      env["SCRIPT_NAME"] || ""
    end

    def request_path
      env["PATH_INFO"]
    end

    def html_formatted_code_block(frame)
      CodeFormatter::HTML.new(frame.filename, frame.line).output
    end

    def text_formatted_code_block(frame)
      CodeFormatter::Text.new(frame.filename, frame.line).output
    end

    def text_heading(char, str)
      str + "\n" + char*str.size
    end

    def inspect_value(obj)
	
		hashed = {}
		begin
			obj.instance_variables.each {|var|
				hashed[var.to_s.delete("@")] = obj.instance_variable_get(var)
			}
			if hashed.blank?
				begin
					hashed = obj.to_hash
				rescue
					return obj.inspect
				end
			end
				
			return JSON.pretty_generate(hashed).gsub("\n", "<br>").gsub(" ", "&nbsp;").gsub('":&nbsp;true', '":&nbsp;<b><span style="color: #f15c21;">true</span></b>').gsub('":&nbsp;false', '":&nbsp;<b><span style="color: #f15c21;">false</span></b>').gsub('":&nbsp;null', '":&nbsp;<b><span style="color: #f15c21;">null</span></b>')
			

		rescue NoMethodError
		  "<span class='unsupported'>(object doesn't support inspect)</span>"
		rescue Exception
		  "<span class='unsupported'>(exception was raised in inspect)</span>"
 
		end
	end

    def inspect_raw_value(obj)
      value = CGI.escapeHTML(obj.inspect)

      if value_small_enough_to_inspect?(value)
        value
      else
        "<span class='unsupported'>(object too large. "\
          "Modify #{CGI.escapeHTML(obj.class.to_s)}#inspect "\
          "or increase BetterErrors.maximum_variable_inspect_size)</span>"
      end
    end

    def value_small_enough_to_inspect?(value)
      return true if BetterErrors.maximum_variable_inspect_size.nil?
      value.length <= BetterErrors.maximum_variable_inspect_size
    end

    def eval_and_respond(index, code)
      result, prompt, prefilled_input = @repls[index].send_input(code)

      {
        highlighted_input: CodeRay.scan(code, :ruby).div(wrap: nil),
        prefilled_input:   prefilled_input,
        prompt:            prompt,
        result:            result
      }
    end
  end
end
