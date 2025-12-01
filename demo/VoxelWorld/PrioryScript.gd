class_name PrioryScript extends Object

#this is designed to parse the scripts stored in the /Resources/Scripts folder
#this is a custom script format that is designed to be easy to read and write

func _init(input:String,mgsl:MGSL.StateDat):
	parse(input,mgsl)

const HEADER_KEYS:Array[String] = ["LOCATION", "TRIGGER", "PLAYER_CHARACTER","PLAYER_ABILITY", "EFFECT", "PRIORITY"]
class Header:
	var Location:MGSL.LocationRef
	var Trigger:String
	var PlayerCharacter:MGSL.CharacterRef
	var PlayerAbility:MGSL.AbilityRef
	var Effect:MGSL.FunctionDat
	var Priority:int
	var OnlyOnce:bool

	func _init():
		pass

	func add_kvp(key:String, value:String,mgsl:MGSL.StateDat):
		match key:
			"LOCATION":
				Location = MGSL.LocationRef.new(value,mgsl)
			"TRIGGER":
				Trigger = value
			"PLAYER_CHARACTER":
				PlayerCharacter = MGSL.CharacterRef.new(value,mgsl)
			"PLAYER_ABILITY":
				PlayerAbility = MGSL.AbilityRef.new(value,mgsl)
			"EFFECT":
				var tokens = value.split(" ",false)
				
				# FunctionDat constructor needs
				# (_name:String,_location:LocationRef,_agent:Quest_Agent_Spec,_args:Array[LAC_Ref],state:StateDat)
				
				var fn_name : String = tokens[0]
				var fn_args_untyped : PackedStringArray = tokens.slice(1,tokens.size())
				
				var fn_args_typed : Array[MGSL.LAC_Ref] = []
				for fn_arg_untyped:String in fn_args_untyped:
					var fn_arg_typed:MGSL.LAC_Ref = MGSL.LAC_Ref.new(fn_arg_untyped,mgsl)
					fn_args_typed.push_back(fn_arg_typed)
					
				var quest_agent_spec:MGSL.Quest_Agent_Spec = MGSL.Quest_Agent_Spec.new([PlayerCharacter.to_char_or_ability()],mgsl.cur_line)
				Effect = MGSL.FunctionDat.new(fn_name,Location,quest_agent_spec,fn_args_typed,mgsl)
			"PRIORITY":
				Priority = int(value)
			"ONLY_ONCE":
				if value.to_upper()=="TRUE":
					OnlyOnce=true
			_:
				printerr("Unknown key: ",key," (line#",mgsl.cur_line,")")


enum LineType { EMPTY, DIALOGUE, COND_IF, COND_ELIF, COND_ELSE, COND_ENDIF, COMMAND, PLAYER_CHOICE, SECTION_JUMP }

class Preposition:
	var preposition:String
	var args:Array[String]
	var line_number:int
	func _init(tokens:Array[String],_line_number):
		if tokens.size()==0:
			printerr("Error parsing command on line ",str(_line_number), " looks like empty brackets to me.")		
		preposition = tokens[0]
		args = args.slice(1)
		line_number=_line_number
		
	
class Command:
	var command:String
	var args:Array[String]
	var line_number:int
	func _init(tokens:Array[String],_line_number:int):
		if tokens.size()==0:
			printerr("Error parsing command on line ",str(_line_number), " looks like empty brackets to me.")		
		command = tokens[0]
		args = tokens.slice(1)
		line_number=_line_number
		

class SpeakerSpecification:
	var is_player:bool
	var character:String # only playercharacters have refs
	var player_choice:Array[MGSL.CharacterRef]
	func _init(_is_player:bool,_character:String,_player_choice:Array[MGSL.CharacterRef]):
		is_player = _is_player
		character = _character
		player_choice = _player_choice
	static func PLAYER()->SpeakerSpecification:
		return SpeakerSpecification.new(true,"",[])
	static func CHARACTER(_character:String)->SpeakerSpecification:
		return SpeakerSpecification.new(false,_character,[])
	static func PLAYER_CHARACTERS(_player_choice:Array[MGSL.CharacterRef])->SpeakerSpecification:
		return SpeakerSpecification.new(true,"",_player_choice)
	static func parse(s:String,mgsl:MGSL.StateDat)->SpeakerSpecification:
		# can look like
		# PLAYER
		# PLAYER (<CHARACTER>)
		# PLAYER (<CHARACTER>/<CHARACTER>/etc.)
		# <CHARACTER>
		if s.begins_with("PLAYER"):
			if s.length() == 6:
				return SpeakerSpecification.PLAYER()
			else:
				var post_parentheses = s.split("(")[1]
				# remove the closing bracket
				if post_parentheses[-1] != ")":
					printerr("Error parsing line ",mgsl.cur_line, " - expected ')' at end of line")
					return SpeakerSpecification.PLAYER()
				post_parentheses = post_parentheses.slice(0,post_parentheses.size()-1)
				var characters:Array[String] = post_parentheses.split("/",false)
				var character_refs:Array[MGSL.CharacterRef] = []
				for character_name:String in characters:
					var chr = mgsl.character(character_name.strip_edges())
					character_refs.push_back(chr)
				return SpeakerSpecification.PLAYER_CHARACTERS(character_refs)
		else:
			return SpeakerSpecification.CHARACTER(s)
		
class ScriptLine:
	var line_number:int
	var line_type:LineType
	var line_s:String

	var section_if_presposition:Preposition
	var section_command:Command

	var section_dialogue_speaker:SpeakerSpecification
	var section_dialogue_text:String

	var section_choice_characterspeed:MGSL.CharacterRef
	var section_choice_text:String

	var section_jump_target:String
	
	func _init(_line_number:int,_line_type:LineType,_line_s:String):
		line_number = _line_number
		line_type = _line_type
		line_s = _line_s

	#EMPTY, DIALOGUE, COND_IF, COND_ELSE, COND_ELIF, COMMAND

	static func EMPTY(_line_number:int,_line_s:String):
		var result : ScriptLine = ScriptLine.new(_line_number,LineType.EMPTY,_line_s)
		return result

	static func DIALOGUE(s:String,mgsl:MGSL.StateDat)->ScriptLine:
		# A line of dialogue looks like one of the following:
		# <CHARACTER>: <DIALOGUE>
		# PLAYER: <DIALOGUE>
		# PLAYER (<CHARACTER>): <DIALOGUE>
		var result : ScriptLine = ScriptLine.new(mgsl.cur_line,LineType.DIALOGUE,s)
		var tokens:PackedStringArray = s.split(":",true)
		if tokens.size() != 2:
			printerr("Error parsing line ",mgsl.cur_line, " - expected ':' in line")
			return ScriptLine.EMPTY(mgsl.cur_line,s)
		var speaker_spec:SpeakerSpecification = SpeakerSpecification.parse(tokens[0],mgsl)
		result.section_dialogue_speaker = speaker_spec
		result.section_dialogue_text = tokens[1].strip_edges()
		return result

	static func COND_IF(preposition:Preposition,_line_number:int,_line_s:String)->ScriptLine:
		var result:ScriptLine = ScriptLine.new(_line_number,LineType.COND_IF,_line_s)
		result.section_if_presposition = preposition
		return result

	static func COND_ELSE(_line_number:int,_line_s:String)->ScriptLine:
		var result : ScriptLine = ScriptLine.new(_line_number,LineType.COND_ELSE,_line_s)
		return result

	static func COND_ELIF(preposition:Preposition,_line_number:int,_line_s:String)->ScriptLine:
		var result:ScriptLine = ScriptLine.new(_line_number,LineType.COND_ELIF,_line_s)
		result.section_if_presposition = preposition
		return result

	static func COND_ENDIF(_line_number:int,_line_s:String):
		var result : ScriptLine = ScriptLine.new(_line_number,LineType.COND_ENDIF,_line_s)
		return result
		
	static func COMMAND(command:Command,_line_number:int,_line_s:String)->ScriptLine:
		var result : ScriptLine = ScriptLine.new(_line_number,LineType.COMMAND,_line_s)
		result.section_command = command
		return result

	static func PLAYER_CHOICE(_line_s:String,mgsl:MGSL.StateDat)->ScriptLine:
		# A player choice looks like one of the following:
		# * <PLAYER_CHOICE>
		# :<PLAYER_CHARACTER>: * <PLAYER_CHOICE>
		var result : ScriptLine = ScriptLine.new(mgsl.cur_line,LineType.PLAYER_CHOICE,_line_s)

		if _line_s[0] ==":":
			var tokens:PackedStringArray = _line_s.split(":",true)
			if tokens.size() != 3:
				printerr("Error parsing line ",mgsl.cur_line, " - expected 3 tokens")
				return ScriptLine.EMPTY(mgsl.cur_line,_line_s)
			var character : MGSL.CharacterRef = MGSL.CharacterRef.new(tokens[1],mgsl)
			result.section_choice_charactersped = character
		
		var choice_text = _line_s.split("*",true,1)[1].strip_edges()	
		result.section_choice_text = choice_text

		return result

	static func SECTION_JUMP(section_name:String,_line_number:int,_line_s:String):
		var result : ScriptLine = ScriptLine.new(_line_number,LineType.SECTION_JUMP,_line_s)
		result.section_jump_target = section_name
		return result

		

func parseLine(s:String,mgsl:MGSL.StateDat)->ScriptLine:
	# a line can look like
	# IF <PREPOSITION>:
	# ELSE:
	# ELIF <PREPOSITION>:
	# ENDIF
	# <CHARACTER>: <DIALOGUE>
	# PLAYER: <DIALOGUE>
	# PLAYER (<CHARACTER>): <DIALOGUE>
	# [ <COMMAND> ] 
	# * <PLAYER_CHOICE>
	# :<CHARACTER>: * <PLAYER_CHOICE>
	# -> <SECTION_NAME>

	var tokenized : PackedStringArray = s.split(" ",false)
	if tokenized.size()==0:
		return ScriptLine.EMPTY(mgsl.cur_line,s)
	var first_token:String = tokenized[0]
	match first_token:
		"IF","ELIF":
			var last_token : String = tokenized[tokenized.size()-1]
			if last_token[-1] == ":":
				#strip the colon
				last_token = last_token.substr(0,last_token.length()-1)
				#if empty, remove token from tokenized
				if last_token == "":
					tokenized = tokenized.slice(0,tokenized.size()-1)
				else:
					tokenized[tokenized.size()-1] = last_token
				var tokens:PackedStringArray = tokenized.slice(1,tokenized.size())
				if tokens.size() == 0:
					printerr("Error parsing line ",mgsl.cur_line, " - expected preposition after IF")
					return ScriptLine.EMPTY(mgsl.cur_line,s)
				else:
					var prep : Preposition = Preposition.new(tokens,mgsl.cur_line)
					if first_token=="IF":
						return ScriptLine.COND_IF(prep,mgsl.cur_line,s)
					else:
						return ScriptLine.COND_ELIF(prep,mgsl.cur_line,s)
						
			else:
				printerr("Error parsing line ",mgsl.cur_line, " - expected ':' at end of line")
				return ScriptLine.EMPTY(mgsl.cur_line,s)
		"ELSE":
			return ScriptLine.COND_ELSE(mgsl.cur_line,s)
		"ENDIF":
			return ScriptLine.COND_ENDIF(mgsl.cur_line,s)
		"*",":":
			return ScriptLine.PLAYER_CHOICE(s,mgsl)
		"->":
			var target = s.split(">",true)[1].strip_edges()
			return ScriptLine.SECTION_JUMP(target,mgsl.cur_line,s)
		"[":
			#last token must be "]"
			var last_token = tokenized[tokenized.size()-1]
			if last_token !="]":
				printerr("Error parsing line ",mgsl.cur_line, " - expected ']' at end of line")
				return ScriptLine.EMPTY(mgsl.cur_line,s)
			tokenized.remove_at(0)
			tokenized.remove_at(tokenized.size()-1)
			var command:Command = Command.new(tokenized,mgsl.cur_line)
			return ScriptLine.COMMAND(command,mgsl.cur_line,s)
		_:
			return ScriptLine.DIALOGUE(s,mgsl)
	

class Section:
	var name:String
	var lines:Array[ScriptLine]
	func _init():
		lines = []

	


const hrow:String = "========================="

class ParsedFile:
	var header:Header
	var sections:Array[Section]
	func _init():
		pass
		

func parse_header(lines:PackedStringArray,parser_state:Dictionary,mgsl:MGSL.StateDat)->Header:
	print("parsing  header")
	var header:Header = Header.new()
	while lines[parser_state.line_number] != hrow && parser_state.line_number<lines.size():
		mgsl.cur_line=parser_state.line_number #cheesy but it works
		var line=lines[parser_state.line_number]
		if line=="":
			parser_state.line_number+=1
			continue
		#split at : into kvp
		var kvp:PackedStringArray = line.split(":",true)
		if kvp.size() != 2:
			printerr("Error parsing header line ",parser_state.line_number)
			parser_state.line_number+=1
			return
		var key:String = kvp[0].strip_edges()
		var value:String = kvp[1].strip_edges()
		header.add_kvp(key,value,mgsl)
		parser_state.line_number+=1
	return header

func parse_section(_lines:PackedStringArray,_parser_state:Dictionary,mgsl:MGSL.StateDat)->Section:
	var result : Section = Section.new()
	# first row is hrow, then section name, then another hrow
	assert(_lines[_parser_state.line_number]==hrow,"expected ==== line on "+str(mgsl.cur_line))
	assert(_lines[_parser_state.line_number+2]==hrow,"expected ==== line on "+str(mgsl.cur_line+2))
	result.name = _lines[_parser_state.line_number+1]	
	print("parsing section ",result.name)
	_parser_state.line_number+=3
	while(_parser_state.line_number<_lines.size() && _lines[_parser_state.line_number] != hrow):
		mgsl.cur_line=_parser_state.line_number
		var line = _lines[_parser_state.line_number]
		if line=="":
			_parser_state.line_number+=1
			continue
		var parsed_line:ScriptLine = parseLine(line,mgsl)
		result.lines.push_back(parsed_line)
		_parser_state.line_number+=1
	
	return result

func parse(input:String,mgsl:MGSL.StateDat):
	var parsed_file:ParsedFile = ParsedFile.new()
	var lines:PackedStringArray = input.split("\n",false)

	for i in range(lines.size()):
		lines[i] = lines[i].split("#",true)[0].strip_edges()
		
	var parser_state:Dictionary = {
		line_number=0,
		section_name="HEADER"
	}

	parsed_file.header = parse_header(lines,parser_state,mgsl)
	
	while parser_state.line_number<lines.size():
		parsed_file.sections.push_back(parse_section(lines,parser_state,mgsl))
	return parsed_file

		

	
