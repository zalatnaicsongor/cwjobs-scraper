require "cwjobs/scraper/version"
require 'net/http'
require 'mechanize'
require 'nokogiri'
require 'uri'
require 'cgi'
require 'sanitize'
require 'json'


module Cwjobs
  class Processor
    def initialize(keyword)
    	@processed = 0
    	@found = 0
		@agent = Mechanize.new
		@job_ids = []
		@keyword = keyword.downcase()
    end

    def start_process()
			@agent.get('https://www.cwjobs.co.uk/JobSearch/Results.aspx?Keywords=' + @keyword) do |page|
                job_count_raw = page.search('.page-header-job-count').text.sub(',', '')
				@found = job_count_raw.to_i
				all = (@found / 20).floor
                puts "found " + @found.to_s + " " + @keyword + " jobs"
				for i in 1..all do
						process_page(i)
				end

				for job_id in @job_ids
					visit_job(job_id)
				end
			end
    end

    def process_page(page_num)
    	page_job_ids = []
			@agent.get('https://www.cwjobs.co.uk/JobSearch/Results.aspx?Keywords=' + @keyword + '&PageNum=' + page_num.to_s) do |page|
				page.encoding = 'ISO-8859-1'
				page.search('div.hd h2 a').map do |job_post|
					job_post_id = CGI.parse(URI.parse(job_post['href']).query)['JobId'].first.to_i
					#puts(job_post_id)
					page_job_ids << job_post_id
					@job_ids << job_post_id
					#puts job_post.text.downcase() + " " + job_post_id.to_s
					@processed = @processed + 1
				end
			end
    end

    def visit_job(job_id)
    	selectors = Hash.new
    	selectors[:title] = Hash.new
    	selectors[:content] = Hash.new


    	selectors[:title][:generic] = "h1.job-title"
    	selectors[:title][:initi8] = "#job_title"
    	selectors[:title][:arcit] = 'h2'
    	selectors[:title][:clientserver] = 'span.style1'

    	selectors[:content][:generic] = "div.job-description"
    	selectors[:content][:initi8]= 'div#detail'
    	selectors[:content][:arcit]= 'div.detail.job-description'
    	selectors[:content][:clientserver] = 'div#content'
    	selectors[:content][:ansonmccade] = 'section.job-description'
        selectors[:content][:capitalone] = 'div#mid'
        selectors[:content][:digitalshadows] = 'div#jobDesc'


    	@agent.get('https://www.cwjobs.co.uk/JobSearch/JobDetails.aspx?JobId=' + job_id.to_s) do |page|
    		page.encoding = 'ISO-8859-1'
    		title = ''
    		content = ''
    		selectors[:title].each_pair do |key, title_selector|
    			title = page.search(title_selector).inner_text.strip
    			if title != '' then
    				title = Sanitize.clean(title)
    				break
    			end
    		end

    		selectors[:content].each_pair do |key, content_selector|
    			content = page.search(content_selector).inner_html.strip
    			if content != '' then
                    content = content.gsub(/<.*?\/?>/, ' ')
                    content = content.gsub(/<\/.*?\/?>/, ' ')
    				content = Sanitize.clean(content)
                    content = content.gsub(/\s+/, ' ')
    				break
    			end
    		end


    		if title == ''
    			puts 'title https://www.cwjobs.co.uk/JobSearch/JobDetails.aspx?JobId=' + job_id.to_s
    		end

    		if content == ''
    			puts 'content https://www.cwjobs.co.uk/JobSearch/JobDetails.aspx?JobId=' + job_id.to_s
    		end

    		File.open("out/"+ @keyword +"/"+ job_id.to_s + ".json", 'w') {|f| f.write(JSON.generate({:content => content, :title => title})) }
    	end
    end


  end

  class Reader
    def initialize()
        @elements = {}
        Dir.chdir("out")
        subdir_list=Dir["*"].reject{|o| not File.directory?(o)}
        subdir_list.each do |subdir|
            visit_dir subdir
        end

        File.open("done.json", 'w') {|f| f.write(JSON.generate(@elements)) }
    end

    def visit_dir(dir_name)
        Dir.chdir(dir_name)
        Dir.glob('*.json') do |json_file|
            visit_file(dir_name, json_file)
        end
        Dir.chdir("../")
    end

    def visit_file(dir_name, file_name)
        id = extract_id(file_name)
        if not @elements.key?(id)
            @elements[id] = {}
            @elements[id]["classes"] = [dir_name]
            file = File.read(file_name)
            data_hash = JSON.parse(file)
            content = data_hash['content'].gsub(/[^a-z ]/i, ' ').downcase.gsub(/\s+/, ' ').strip;
            title = data_hash['title'].gsub(/[^a-z ]/i, ' ').downcase.gsub(/\s+/, ' ').strip;
            @elements[id]["title"] = title
            @elements[id]["content"] = content
            @elements[id]["text"] = title + " " + content
        else 
            @elements[id]["classes"] << dir_name
        end
    end

    def extract_id(file_name)
        file_name[0..-6]
    end
  end

end