require 'nokogiri'

module OcrAlto
  
  # detect potential headlines and their subheads based on information in the ALTO file
  def self.detect_headlines_from_alto(alto_url, max_num_headlines: 16)
  	doc = Nokogiri::XML(open(alto_url))
	  # ALTO XMLs may have inconsistent namespaces
	  doc.remove_namespaces!

	  page = doc.xpath("//Page").first
	  page_width = page['WIDTH'].to_i
	  page_height = page['HEIGHT'].to_i

	  # calculate median line height
	  line_heights = doc.xpath("//TextLine/@HEIGHT")
	  line_heights = line_heights.sort {|x, y| x.value.to_f <=> y.value.to_f}
	  len = line_heights.length
	  median_line_height = line_heights[len / 2].value.to_f

	  # puts "Median line height is #{median_line_height}"

	  # hueristically determine the top headlines
	  headline_height_factor = 1.7
	  subhead_height_factor = 1.25
	  headline_gap_factor = 2.5
	  max_lines_per_headline = 16
	  headline_min_lenght = 0.08 # percent of page width
	  headline_min_top = 0.04 # percent of page height

	  headlines = []
	  # headlines do not across TextBlocks
	  doc.xpath("//TextBlock").each do |tb|
	    headline = nil
	    tb.xpath("TextLine").each do |tl|
	      if tl['HEIGHT'].to_f > median_line_height * headline_height_factor or
	            tl['HEIGHT'].to_f > median_line_height * subhead_height_factor
	        # find potential headline or subhead
	        if headline.nil?
	          if tl['HEIGHT'].to_f > median_line_height * headline_height_factor
	            headline = { left: tl['HPOS'].to_f,
	                         right: tl['HPOS'].to_f + tl['WIDTH'].to_f,
	                         top: tl['VPOS'].to_f,
	                         bottom: tl['VPOS'].to_f + tl['HEIGHT'].to_f,
	                         lines: [tl.clone],
	                         max_line_height: tl['HEIGHT'].to_f
	                        }
	          end
	        else
	          if tl['VPOS'].to_f - headline[:bottom] < headline_gap_factor * tl['HEIGHT'].to_f
	            # closer enough to current headline, include it as subhead
	            headline[:left] = tl['HPOS'].to_f if tl['HPOS'].to_f < headline[:left]
	            headline[:right] = tl['HPOS'].to_f + tl['WIDTH'].to_f if tl['HPOS'].to_f + tl['WIDTH'].to_f > headline[:right]
	            headline[:top] = tl['VPOS'].to_f if tl['VPOS'].to_f < headline[:top]
	            headline[:bottom] = tl['VPOS'].to_f + tl['HEIGHT'].to_f if tl['VPOS'].to_f + tl['HEIGHT'].to_f > headline[:bottom]
	            headline[:lines] =  headline[:lines] << tl.clone
	            headline[:max_line_height] = tl['HEIGHT'].to_f if tl['HEIGHT'].to_f > headline[:max_line_height]
	          else
	            # apart from current headline. Consider it as a different headline
	            headlines << headline
	            headline = nil
	            if tl['HEIGHT'].to_f > median_line_height * headline_height_factor
	              # new headline
	              headline = { left: tl['HPOS'].to_f,
	                           right: tl['HPOS'].to_f + tl['WIDTH'].to_f,
	                           top: tl['VPOS'].to_f,
	                           bottom: tl['VPOS'].to_f + tl['HEIGHT'].to_f,
	                           lines: [tl.clone],
	                           max_line_height: tl['HEIGHT'].to_f
	                          }
	            end
	          end
	        end
	      end
	    end # tb.xpath("TextLine").each
	    # create last classification
	    if !headline.nil?
	      headlines << headline
	    end
	  end # doc.xpath("//TextBlock").each

	  #
	  # process headlines
	  #

	  # remove headlines which are too close to the top
	  # they could be masthead, nameplate etc
	  headlines = headlines.select do |headline|
	    headline[:top] / page_height > headline_min_top
	  end

	  # if headlind contains too many lines
	  # remove some lines until within limit
	  headlines.each do |headline|
	    factor = subhead_height_factor
	    trimmed = false
	    until headline[:lines].length <= max_lines_per_headline
	      new_lines = []
	      trimmed = true
	      factor += 0.1
	      for i in 0..headline[:lines].length-1
	        if headline[:lines][i]['HEIGHT'].to_f >= median_line_height * factor
	          new_lines << headline[:lines][i]
	        else
	          break
	        end
	      end
	      headline[:lines] = new_lines
	    end # until loop
	    if trimmed
	      # recalulate box
	      headline[:left] = 99999999999999
	      headline[:right] = 0
	      headline[:top] = 99999999999999
	      headline[:bottom] = 0
	      headline[:max_line_height] = 0

	      headline[:lines].each do |tl|
	        headline[:left] = tl['HPOS'].to_f if tl['HPOS'].to_f < headline[:left]
	        headline[:right] = tl['HPOS'].to_f + tl['WIDTH'].to_f if tl['HPOS'].to_f + tl['WIDTH'].to_f > headline[:right]
	        headline[:top] = tl['VPOS'].to_f if tl['VPOS'].to_f < headline[:top]
	        headline[:bottom] = tl['VPOS'].to_f + tl['HEIGHT'].to_f if tl['VPOS'].to_f + tl['HEIGHT'].to_f > headline[:bottom]
	        headline[:max_line_height] = tl['HEIGHT'].to_f if tl['HEIGHT'].to_f > headline[:max_line_height]
	      end
	    end

	  end

	  # merge headlines that are close to each other
	  headlines = headlines.sort {|x, y| x[:top] <=> y[:top]}
	  headlines = headlines.select.with_index do |headline, index|
	    merged = false
	    for i in 0..index
	      if headlines[i][:bottom] < headline[:top] && 
	           headline[:top] - headlines[i][:bottom] < headline_gap_factor * headline[:max_line_height] &&
	           (headline[:left] - headlines[i][:left]).abs / page_width <= 0.06 &&
	           (headline[:right] - headlines[i][:right]).abs / page_width <= 0.06 &&
	           headlines[i][:lines].length + headline[:lines].length <= max_lines_per_headline
	        # merge with headline[i]
	        headlines[i][:left] = headline[:left] if headline[:left] < headlines[i][:left]
	        headlines[i][:right] = headline[:right] if headline[:right] > headlines[i][:right]
	        headlines[i][:top] = headline[:top] if headline[:top] < headlines[i][:top]
	        headlines[i][:bottom] = headline[:bottom] if headline[:bottom] > headlines[i][:bottom]
	        headlines[i][:lines] += headline[:lines]
	        headlines[i][:max_line_height] = headline[:max_line_height] if headline[:max_line_height] > headlines[i][:max_line_height]
	        merged = true
	        break
	      end
	    end
	    !merged
	  end

	  # remove headlines which are too short
	  headlines = headlines.select do |headline|
	    (headline[:right] - headline[:left]) / page_width > headline_min_lenght
	  end
	  
	  # limit number of headlines
	  if headlines.length > max_num_headlines
	    # sort by reverse line height
	    headlines = headlines.sort {|x, y| y[:max_line_height] <=> x[:max_line_height]}
	    headlines = headlines[0..max_num_headlines-1]
	  end

	  return {
	  	page_width: page_width,
	  	page_height: page_height,
	  	headlines: headlines
	  }
  end

  # box1 overlaps box2
  def self.overlap(box1, box2)
  	! (box1[:hpos] + box1[:width] < box2[:hpos] ||
  		 box1[:hpos] > box2[:hpos] + box2[:width] ||
  		 box1[:vpos] + box1[:height] < box2[:vpos] ||
  		 box1[:vpos] > box2[:vpos] + box2[:height])
  end

  # box1 encloses box2
  def self.enclose(box1, box2)
  	box1[:hpos] <= box2[:hpos] &&
  	box1[:hpos] + box1[:width] >= box2[:hpos] + box2[:width] &&
  	box1[:vpos] <= box2[:vpos] &&
  	box1[:vpos] + box1[:height] >= box2[:vpos] + box2[:height]
  end

  # extract ORC text inside of box from the ALTO file
  # box should have keys such as hpos, vpos, width, height
  # values are normalized to image with width = 1 and height = 1
  def self.extract_text_from_alto(alto_url, nbox)
  	text = ""
  	doc = Nokogiri::XML(open(alto_url))
	  # ALTO XMLs may have inconsistent namespaces
	  doc.remove_namespaces!

	  page = doc.xpath("//Page").first
	  page_width = page['WIDTH'].to_i
	  page_height = page['HEIGHT'].to_i

	  box = {
	  	hpos: nbox[:hpos] * page_width,
	  	vpos: nbox[:vpos] * page_height,
	  	width: nbox[:width] * page_width,
	  	height: nbox[:height] * page_height,
	  }

	  doc.xpath("//TextBlock").each do |tb|
	  	if overlap({hpos:tb['HPOS'].to_f, vpos:tb['VPOS'].to_f, width:tb['WIDTH'].to_f, height:tb['HEIGHT'].to_f}, box)
		    tb.xpath(".//String").each do |str|
		    	if enclose(box, {hpos: str['HPOS'].to_f, vpos: str['VPOS'].to_f, width: str['WIDTH'].to_f, height: str['HEIGHT'].to_f})
		    		text << " " << str['CONTENT']
		    	end
		    end
		  end
		  text = text.strip
		  text << "\n"
	  end # doc.xpath("//TextBlock").each
	  text.strip
  end


  # extract headline and subheads inside of box from the ALTO file
  # box should have keys such as hpos, vpos, width, height
  # values are normalized to image with width = 1 and height = 1
  def self.extract_headline_from_alto(alto_url, nbox)
  	text = ""
  	doc = Nokogiri::XML(open(alto_url))
	  # ALTO XMLs may have inconsistent namespaces
	  doc.remove_namespaces!

	  page = doc.xpath("//Page").first
	  page_width = page['WIDTH'].to_i
	  page_height = page['HEIGHT'].to_i

	  box = {
	  	hpos: nbox[:hpos] * page_width,
	  	vpos: nbox[:vpos] * page_height,
	  	width: nbox[:width] * page_width,
	  	height: nbox[:height] * page_height,
	  }

	  headline = ""
	  subheads = ""
	  is_headline = true
	  headline_bottom = 0
	  doc.xpath("//TextBlock").each do |tb|
	  	if overlap({hpos:tb['HPOS'].to_f, vpos:tb['VPOS'].to_f, width:tb['WIDTH'].to_f, height:tb['HEIGHT'].to_f}, box)
		    tb.xpath("TextLine").each do |tl|
		    	# determin if this text line is no longer part of the headline
		    	if headline != "" && headline_bottom != 0 && tl['VPOS'].to_f - headline_bottom > tl['HEIGHT'].to_f
		    		# too far apart from the headline
		    		is_headline = false
		    	end
		    	if is_headline && tl['VPOS'].to_f + tl['HEIGHT'].to_f > headline_bottom
		    		headline_bottom = tl['VPOS'].to_f + tl['HEIGHT'].to_f
		    	end
		    	tl.xpath("String").each do |str|
			    	if enclose(box, {hpos: str['HPOS'].to_f, vpos: str['VPOS'].to_f, width: str['WIDTH'].to_f, height: str['HEIGHT'].to_f})
			    		if is_headline
			    		  headline << " " << str['CONTENT']
			    		else
			    			subheads << " " << str['CONTENT']
			    		end
			    	end
			    end
		    end
		  end
		  if !is_headline
		  	# insert new line to subheads at the end of each text block
		  	subheads = subheads.strip
		  	subheads << "\n"
		  end
	  end # doc.xpath("//TextBlock").each
	  puts "HEADLINE: #{headline.strip}"
	  puts "SUBHEADS: #{subheads.strip}"
	  [headline.strip, subheads.strip]
  end

end