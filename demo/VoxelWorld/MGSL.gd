class_name MGSL extends Object

class LocationRef:
	var name:String
	func _init(_name:String,state:StateDat):
		self.name=_name
		if state!=null && !state.ENUMS.Location.has(_name):
			state.err("Unknown location: '"+_name+"'")
	func _to_string()->String:
		return self.name
	func equals(other:LocationRef)->bool:
		return self.name==other.name
	func copy()->LocationRef:
		return LocationRef.new(name,null)

class AbilityRef:
	var name:String
	func _init(_name:String,state:StateDat):
		self.name=_name
		if state!=null && !state.ENUMS.Abilities.has(_name):
			state.err("Unknown ability: '"+_name+"'")			
	func _to_string()->String:
		return self.name
	func equals(other:AbilityRef)->bool:
		return self.name==other.name
	func copy()->AbilityRef:
		return AbilityRef.new(name,null)

class CharacterRef:
	var name:String
	func _init(_name:String,state:StateDat):
		self.name=_name
		if state!=null && !state.ENUMS.Characters.has(_name):
			state.err("Unknown character: '"+_name+"'")			
	func _to_string()->String:
		return self.name
	func equals(other:CharacterRef)->bool:
		return self.name==other.name	
	func copy()->CharacterRef:
		return CharacterRef.new(name,null)	
	func to_char_or_ability()->CharacterOrAbilityRef:
		return CharacterOrAbilityRef.new(name,null)
		
class CharacterOrAbilityRef:
	var name:String
	var is_character:bool
	var is_ability:bool
	func get_character(line_number:int=-1)->CharacterRef:
		if !is_character:
			printerr("Expected character, got: '"+name+"' (line# ",line_number,")")
		return CharacterRef.new(name,null)
	func get_ability(line_number:int=-1)->AbilityRef:
		if !is_ability:
			printerr("Expected ability, got: '"+name+"' (line# ",line_number,")")
		return AbilityRef.new(name,null)
	func _init(_name:String,state:StateDat):
		self.name=_name
		if state!=null:
			is_character = state.ENUMS.Characters.has(_name)
			is_ability = state.ENUMS.Abilities.has(_name)
			if !is_character && !is_ability:
				state.err("Unknown character or ability: '"+_name+"'")	
	func _to_string()->String:
		return self.name
	func equals(other:CharacterOrAbilityRef)->bool:
		return self.name==other.name
	func copy()->CharacterOrAbilityRef:
		var result = CharacterOrAbilityRef.new(name,null)
		result.is_character = is_character
		result.is_ability = is_ability
		return result

# reference to Location, Ability, or Character
class LAC_Ref:
	var name:String
	var is_location:bool
	var is_ability:bool
	var is_character:bool
	func get_location(line_number:int=-1)->LocationRef:
		if !is_location:
			printerr("Expected location, got: '"+name+"' (line# ",line_number,")")
		return LocationRef.new(name,null)
	func get_ability(line_number:int=-1)->AbilityRef:
		if !is_ability:
			printerr("Expected ability, got: '"+name+"' (line# ",line_number,")")
		return AbilityRef.new(name,null)
	func get_character(line_number:int=-1)->CharacterRef:
		if !is_character:
			printerr("Expected character, got: '"+name+"' (line# ",line_number,")")
		return CharacterRef.new(name,null)
	func _init(_name:String,state:StateDat):
		self.name=_name
		if state!=null:
			is_location = state.ENUMS.Location.has(_name)
			is_ability = state.ENUMS.Abilities.has(_name)
			is_character = state.ENUMS.Characters.has(_name)
			if !is_location && !is_ability && !is_character:
				state.err("Unknown location, ability, or character: '"+_name+"'")						
	func _to_string()->String:
		return self.name
	func equals(other:LAC_Ref)->bool:
		return self.name==other.name
	func copy()->LAC_Ref:
		var result = LAC_Ref.new(name,null)
		result.is_location = is_location
		result.is_ability = is_ability
		result.is_character = is_character
		return result

class AbilityHierarchyDat:
	var greater:AbilityRef
	var lesser:AbilityRef
	var line_number:int
	func _init(_greater:AbilityRef,_lesser:AbilityRef,_line_number:int):
		self.greater=_greater
		self.lesser=_lesser
		self.line_number=_line_number		
	func _to_string()->String:
		return self.greater.name+">"+self.lesser.name
	func equals(other:AbilityHierarchyDat)->bool:
		return greater.equals(other.greater) \
			&& lesser.equals(other.lesser) \
			&& line_number==other.line_number
	func copy()->AbilityHierarchyDat:
		return AbilityHierarchyDat.new(greater.copy(),lesser.copy(),line_number)

#[from, to_declaration, restrictions, cur_line]	
class ConnectionDat:
	var from:LocationRef
	var to:LocationRef
	var restrictions:Array[CharacterOrAbilityRef]
	var line_number:int
	func _init(_from:LocationRef,_to:LocationRef,_restrictions:Array[CharacterOrAbilityRef],_line_number:int):
		self.from=_from
		self.to=_to
		self.restrictions=_restrictions
		self.line_number=_line_number		
	func _to_string()->String:
		var s=self.from.name
		s+=" -> "+self.to.name
		if self.restrictions.size()>0:
			s+=" ["
			for i in range(self.restrictions.size()):
				s+=self.restrictions[i].name
				if i<self.restrictions.size()-1:
					s+=" or "
			s+="]"
		return s
	func flip()->ConnectionDat:
		return ConnectionDat.new(to,from,restrictions,line_number)
		
	func equals(other:ConnectionDat)->bool:
		return from.equals(other.from) \
			&& to.equals(other.to) \
			&& restrictions==other.restrictions \
			&& line_number==other.line_number 
	func copy()->ConnectionDat:
		var restrictions_copy : Array[CharacterOrAbilityRef] = []
		for restriction in restrictions:
			restrictions_copy.push_back(restriction.copy())
		var result = ConnectionDat.new(from.copy(),to.copy(),restrictions_copy,line_number)
		return result

class CharacterDat:
	var Location:LocationRef
	var Abilities:Array[AbilityRef]
	func _init():
		self.Location=null
		self.Abilities=[]	
	func _to_string()->String:
		var s="Location: "+self.Location.name+"\n"
		s+="Abilities:\n"
		for ability in self.Abilities:
			s+="\t"+ability.name+"\n"
		s=s.substr(0,s.length()-1)		
		return s
	func equals(other:CharacterDat)->bool:
		return Location.equals(other.Location) && Abilities==other.Abilities
	func has_ability(ability:AbilityRef)->bool:
		for other:AbilityRef in Abilities:
			if other.equals(ability):
				return true
		return false
	func copy()->CharacterDat:
		var result = CharacterDat.new()
		result.Location = Location.copy()
		for ability in Abilities:
			result.Abilities.push_back(ability.copy())
		return result

class ENUM_Catalogue:
	var Location:Array[String]
	var Abilities:Array[String]
	var Characters:Array[String]
	func _init():
		self.Location=[]
		self.Abilities=[]
		self.Characters=[]
	func _to_string() -> String:
		var s="Location:\n"
		for location in self.Location:
			s+="\t"+location+"\n"
		s+="Abilities:\n"
		for ability in self.Abilities:
			s+="\t"+ability+"\n"
		s+="Characters:\n"
		for character in self.Characters:
			s+="\t"+character+"\n"
		return s
	func equals(other:ENUM_Catalogue)->bool:
		return Location==other.Location \
			&& Abilities==other.Abilities \
			&& Characters==other.Characters
	func copy()->ENUM_Catalogue:
		var result = ENUM_Catalogue.new()
		for location in Location:
			result.Location.push_back(location)
		for ability in Abilities:
			result.Abilities.push_back(ability)
		for character in Characters:
			result.Characters.push_back(character)
		return result

# quest_agent_spec can look like (CHARACTER) ABILITY or just ABILITY or CHARACTER

class Quest_Agent_Spec:
	var restriction:CharacterOrAbilityRef
	var character_check:CharacterRef
	var is_ability_filter:bool
	var is_character_filter:bool
	var has_character_spec:bool
	func get_ability_filter(line_no:int=-1)->AbilityRef:
		if !is_ability_filter:
			printerr("Expected ability filter, got: '"+restriction.name+"' (line# ",line_no,")")
		return AbilityRef.new(restriction.name,null)
	func get_character_filter(line_no:int=-1)->CharacterRef:
		if !is_character_filter:
			printerr("Expected character filter, got: '"+restriction.name+"' (line# ",line_no,")")
		return CharacterRef.new(restriction.name,null)
	func _init(dats:Array[CharacterOrAbilityRef],line_no:int=-1):
		if dats.size() == 1:
			restriction = dats[0]
			has_character_spec = false
			is_ability_filter = restriction.is_ability
			is_character_filter = restriction.is_character
		elif dats.size() == 2:
			restriction = dats[1]
			character_check = dats[0].get_character()
			has_character_spec = true
			is_ability_filter = restriction.is_ability
			is_character_filter = restriction.is_character
		else:
			printerr("Expected 1 or 2 arguments, got: ",dats.size()," (line# ",line_no,")")
	func _to_string() -> String:
		if has_character_spec:
			return "("+str(character_check)+") "+str(restriction)
		return restriction.name
	func equlas(other:Quest_Agent_Spec)->bool:
		return restriction.equals(other.restriction) \
			&& character_check.equals(other.character_check) 
	func copy()->Quest_Agent_Spec:
		var dats : Array[CharacterOrAbilityRef] = []
		if is_ability_filter:
			dats.push_back(restriction.copy())
		elif has_character_spec:
			dats.push_back(character_check.copy())
			dats.push_back(restriction.copy())
		else:
			dats.push_back(restriction.copy())
		var result = Quest_Agent_Spec.new(dats,-1)
		return result

# A Function looks like one of
# UNLOCK CHARACTER
# FREE_PASSAGE_TO_AND_FROM LOCATION
# ADD_ABILITY ABILITY CHARACTER
class FunctionDat:
	var name:String
	var args:Array[LAC_Ref]
	var source_location:LocationRef
	var source_agent:CharacterRef
	func _init(_name:String,_location:LocationRef,_agent:Quest_Agent_Spec,_args:Array[LAC_Ref],state:StateDat):
		self.name=_name
		self.args=_args
		if state!=null:
			match name:
				"UNLOCK":
					if args.size() != 1:
						state.err("Expected 1 argument, got: "+str(args.size()))
					if !args[0].is_character:
						state.err("Expected character, got: "+args[0].name)
				"FREE_PASSAGE_TO_AND_FROM":
					if args.size() != 1:
						state.err("Expected 1 argument, got: "+str(args.size()))
					if !args[0].is_location:
						state.err("Expected location, got: "+args[0].name)
					self.source_location= _location
				"ADD_ABILITY":
					if args.size() != 1:
						state.err("Expected 1 argument, got: "+str(args.size()))
					if !args[0].is_ability:
						state.err("Expected ability, got: "+args[0].name)
					self.source_agent=_agent.get_character_filter(state.cur_line)
				_:
					state.err("Unknown function name: '"+name+"'")
	func _to_string() -> String:
		var s=self.name
		for arg in self.args:
			s+=" "+str(arg)
		return s
	func equals(other:FunctionDat)->bool:
		if name!=other.name || args.size()!=other.args.size():
			return false
		for i in range(args.size()):
			if !args[i].equals(other.args[i]):
				return false
		return true
	func copy()->FunctionDat:
		var args_copy : Array[LAC_Ref] = []
		for arg in args:
			args_copy.push_back(arg.copy())
		var _agent : Quest_Agent_Spec
		if source_agent==null:
			_agent = null
		else:
			_agent = Quest_Agent_Spec.new([CharacterOrAbilityRef.new(source_agent.name,null)],-1)
		var result = FunctionDat.new(name,source_location,_agent,args_copy,null)
		return result

# A quest looks like
# [quest_agent_spec, location, functions, cur_line]

class QuestDat:
	var agent:Quest_Agent_Spec
	var location:LocationRef
	var functions:Array[FunctionDat]
	var line_number:int
	func _init(_agent:Quest_Agent_Spec,_location:LocationRef,_functions:Array[FunctionDat],_line_number:int):
		self.agent=_agent
		self.location=_location
		self.functions=_functions
		self.line_number=_line_number
	func _to_string() -> String:
		var s=str(agent)+" in "+str(location)+" -> "
		for function in functions:
			s+=str(function)+", "
		return s.substr(0,s.length()-2)
	func equals(other:QuestDat)->bool:
		if !agent.equals(other.agent) || !location.equals(other.location) || functions.size()!=other.functions.size():
			return false
		for i in range(functions.size()):
			if !functions[i].equals(other.functions[i]):
				return false
		return true
	func copy()->QuestDat:
		var functions_copy : Array[FunctionDat] = []
		for function in functions:
			functions_copy.push_back(function.copy())
		var result = QuestDat.new(agent.copy(),location.copy(),functions_copy,line_number)
		return result

class StateDat:
	var ENUMS : ENUM_Catalogue 
	var ABILITY_HIERARCHY: Array[AbilityHierarchyDat]
	var CHARACTERS : Dictionary[String,CharacterDat] # key is CharacterRef
	var CONNECTIONS : Array[ConnectionDat]
	var QUESTS : Array[QuestDat]
	var unlocked_characters:Array[CharacterRef]
	var actions_this_turn:Array[QuestDat]
	
	#used when during construction for error messages
	var cur_line:int	
	var character_domains:Dictionary[String,Array] #  [ CharacterRef, Array[LocationRef] ] 
	var location_occupancy:Dictionary[String,Array] # [ LocationRef, Array[CharacterRef] ] 

	func _to_string() -> String:
		var s="ENUMS:\n"
		s+=self.ENUMS._to_string()+"\n"
		s+="ABILITY_HIERARCHY:\n"
		for ability_hierarchy in self.ABILITY_HIERARCHY:
			s+=Glob.indent(ability_hierarchy._to_string())+"\n"
		s+="CHARACTERS:\n"
		for character_ref : String in self.CHARACTERS:
			s+="\t"+character_ref+"\n"
			s+=Glob.indent(self.CHARACTERS[character_ref]._to_string())+"\n"
		s+="CONNECTIONS:\n"
		for connection in self.CONNECTIONS:
			s+=Glob.indent(connection._to_string())+"\n"	
		s+="QUESTS:\n"
		for quest in self.QUESTS:
			s+=Glob.indent(quest._to_string())+"\n"
		s+="unlocked_characters:\n"
		for chr in self.unlocked_characters:
			s+="\t"+chr.name+"\n"
		s+="actions_this_turn:\n"
		for action in self.actions_this_turn:
			s+=Glob.indent(action._to_string())+"\n"			
		return s
	
	func _init():
		self.ENUMS= ENUM_Catalogue.new()
		self.ABILITY_HIERARCHY=[]
		self.CHARACTERS={}
		self.CONNECTIONS=[]
		self.QUESTS=[]
		self.unlocked_characters=[]
		self.actions_this_turn=[]
		self.cur_line=0		
		self.character_domains={}  
		self.location_occupancy={} 
		
	func is_char_unlocked(chr:CharacterRef):
		for other:CharacterRef in unlocked_characters:
			if other.equals(chr):
				return true
		return false
		
	func location(location_name:String)->LocationRef:
		return LocationRef.new(location_name,self)
	func ability(ability_name:String)->AbilityRef:
		return AbilityRef.new(ability_name,self)
	func character(character_name:String)->CharacterRef:
		return CharacterRef.new(character_name,self)
	func character_or_ability(ac_name:String)->CharacterOrAbilityRef:
		return CharacterOrAbilityRef.new(ac_name,self)
	func LAC(ac_name:String)->LAC_Ref:
		return LAC_Ref.new(ac_name,self)
	func equals(other:StateDat)->bool:
		#	var ENUMS : ENUM_Catalogue 
		if !ENUMS.equals(other.ENUMS):
			return false
		
		# var ABILITY_HIERARCHY: Array[AbilityHierarchyDat]
		if ABILITY_HIERARCHY.size()!=other.ABILITY_HIERARCHY.size():
			return false
		for i in range(ABILITY_HIERARCHY.size()):
			if !ABILITY_HIERARCHY[i].equals(other.ABILITY_HIERARCHY[i]):
				return false

		# var CHARACTERS : Dictionary[String,CharacterDat] # key is CharacterRef
		var characters_keys = CHARACTERS.keys()
		var other_characters_keys = other.CHARACTERS.keys()
		if characters_keys!=other_characters_keys:
			return false
		for character_key in characters_keys:
			if !CHARACTERS[character_key].equals(other.CHARACTERS[character_key]):
				return false

		# var CONNECTIONS : Array[ConnectionDat]
		if CONNECTIONS.size()!=other.CONNECTIONS.size():
			return false
		for i in range(CONNECTIONS.size()):
			if !CONNECTIONS[i].equals(other.CONNECTIONS[i]):
				return false

		# var QUESTS : Array[QuestDat]
		if QUESTS.size()!=other.QUESTS.size():
			return false
		for i in range(QUESTS.size()):
			if !QUESTS[i].equals(other.QUESTS[i]):
				return false

		# var unlocked_characters:Array[CharacterRef]
		if unlocked_characters.size()!=other.unlocked_characters.size():
			return false
		for i in range(unlocked_characters.size()):
			if !unlocked_characters[i].equals(other.unlocked_characters[i]):
				return false

		# var actions_this_turn:Array[QuestDat]
		if actions_this_turn.size()!=other.actions_this_turn.size():
			return false
		for i in range(actions_this_turn.size()):
			if !actions_this_turn[i].equals(other.actions_this_turn[i]):
				return false

		if cur_line != other.cur_line:
			return false
			
		return true
		
	func err(s:String, line_number:int=-1):
		if line_number==-1:
			line_number=cur_line
		printerr(s," (line# ",line_number,")")
		
	func valid_enum_type(s:String)->bool:
		return s=="Location" || s=="Abilities" || s=="Characters"

	func copy()->StateDat:		
		var result = StateDat.new()	
		# var ENUMS : ENUM_Catalogue 
		result.ENUMS = ENUMS.copy()
		# var ABILITY_HIERARCHY: Array[AbilityHierarchyDat]
		for ability_hierarchy_dat in ABILITY_HIERARCHY:
			result.ABILITY_HIERARCHY.push_back(ability_hierarchy_dat.copy())
		# var CHARACTERS : Dictionary[String,CharacterDat] # key is CharacterRef
		for character_key in CHARACTERS.keys():
			result.CHARACTERS[character_key] = CHARACTERS[character_key].copy()
		# var CONNECTIONS : Array[ConnectionDat]
		for connection_dat in CONNECTIONS:
			result.CONNECTIONS.push_back(connection_dat.copy())
		# var QUESTS : Array[QuestDat]
		for quest_dat in QUESTS:
			result.QUESTS.push_back(quest_dat.copy())
		# var unlocked_characters:Array[CharacterRef]
		for chr in unlocked_characters:
			result.unlocked_characters.push_back(chr.copy())
		# var actions_this_turn:Array[QuestDat]
		for quest_dat in actions_this_turn:
			result.actions_this_turn.push_back(quest_dat.copy())
		result.cur_line = cur_line		
		# var character_domains:Dictionary[String,Array]={} #  [ CharacterRef, Array[LocationRef] ] 
		result.character_domains = self.character_domains.duplicate() #uh, these are read-only anyway...		
		# var location_occupancy:Dictionary[String,Array]={} # [ LocationRef, Array[CharacterRef] ]
		result.location_occupancy = self.location_occupancy.duplicate() #uh, these are read-only anyway... 
		
		return result
		
		

var mgsl:StateDat=StateDat.new()

var lines:PackedStringArray
var playthrough:Array[StateDat]=[] 

enum Section {
	INITIAL, ENUMS,ABILITY_HIERARCHY,CHARACTERS,CONNECTIONS,QUESTS
}

const VALID_FUNCTION_NAMES = ["UNLOCK", "FREE_PASSAGE_TO_AND_FROM", "ADD_ABILITY"]

var alphanum = RegEx.new()

func err(s:String, line_number:int=-1):
	if line_number==-1:
		line_number=cur_line
	printerr(s," (line# ",line_number,")")

func check_word(s):
	#checks if string is alphanumeric
	var mat : RegExMatch = alphanum.search(s)
	var correct : bool =  mat!=null && mat.strings.size() == 1 && mat.strings[0] == s
	if !correct:
		err("Expected alphanumeric word, got: '"+s+"',")
	return s
	
func parse_line(parser_state:ParserState, line_no:int, line:String)->void:
	#strip // comments
	if line.find("//") != -1:
		line = line.split("//")[0]
	
	line = line.strip_edges()
	if line == "":
		return

	#ignore line if consists of "="s only
	if line.find("=") == 0 && line.rfind("=") == line.length()-1:
		return

	match parser_state.section:
		Section.INITIAL:
			if line==Section.find_key(Section.ENUMS):
				parser_state.section = Section.ENUMS
			else:
				err("Expected ENUMS section, got: '"+line+"'")

		Section.ENUMS:
			# enums line looks like a list of enum declarations
			# Location:
			# 	TOWN, HOME, CASTLE, CHURCH, SCHOOL, WELL, WOODS, MOUNTAIN, UNDERGROUND, HEAVEN
			# newlines are allowed. let's assume a new declaration is a line with a single
			# word followed by a colon
			if line.find(":") != -1:
				var parts = line.split(":")
				var new_enum_type_name = check_word(parts[0].strip_edges())
				if mgsl.ENUMS[new_enum_type_name].size()>0:
					err("Enum type already declared: '"+new_enum_type_name+"'")
				#only allowed enum types are LOCATION, ABILITIES, CHARACTERS
				if !mgsl.valid_enum_type(new_enum_type_name):
					err("Unknown enum type: '"+new_enum_type_name+"'")
				parser_state.cur_enum_declaration = new_enum_type_name
				if parts.size() > 1 && parts[1].strip_edges() != "":
					parse_line(parser_state,line_no,parts[1])
			elif line=="ABILITY_HIERARCHY":
				parser_state.section = Section.ABILITY_HIERARCHY
			else:
				var items = line.split(",")
				for i in range(items.size()):
					mgsl.ENUMS[parser_state.cur_enum_declaration].push_back(check_word(items[i].strip_edges()))

		Section.ABILITY_HIERARCHY:		
			# lines in this section look like
			# LONGJUMP > JUMP			
			var tokens = line.split(">")
			if line=="CHARACTERS":
				parser_state.section = Section.CHARACTERS
				return
			if tokens.size() != 2:
				err("Expected 'A > B' format, got: '"+line+"'")
			var greater : AbilityRef = mgsl.ability(tokens[0].strip_edges())
			var lesser : AbilityRef  = mgsl.ability(tokens[1].strip_edges())
			var hierarchy_entry:AbilityHierarchyDat = AbilityHierarchyDat.new(greater,lesser,cur_line)
			mgsl.ABILITY_HIERARCHY.push_back(hierarchy_entry)				
		Section.CHARACTERS:
			# A character declaration looks like
			# BOY:
			#	Location: TOWN
			#	Abilities: VINE_HANG
						
			if line=="CONNECTIONS":
				parser_state.section = Section.CONNECTIONS
				return

			# if line ends with a colon, it's a character name
			if line.find(":") == line.length()-1:
				parser_state.cur_character = mgsl.character(line.split(":")[0])
				mgsl.CHARACTERS[parser_state.cur_character.name] = CharacterDat.new()
			# if there's a colon inside the line, then it's an ability
			elif line.find(":") != -1:
				var parts = line.split(":")
				if parts.size() != 2:
					err("Expected 'A: B' format, got: '"+line+"'")
				var ability = check_word(parts[0].strip_edges())
				var values = parts[1].strip_edges().split(",")
				if values.size() == 0:
					err("Expected values, got: '"+parts[1]+"'")
				for i in range(values.size()):
					values[i] = check_word(values[i].strip_edges())

				#ability has to be "Location" or "Abilities"
				if ability != "Location" && ability != "Abilities":
					err("Unknown ability: '"+ability+"'")

				#Location has to be a known Location enum
				if ability == "Location":
					#there can only b eone location
					if values.size() != 1:
						err("Expected single location, got: '"+parts[1]+"'")
					var location : LocationRef = mgsl.location(values[0])
					mgsl.CHARACTERS[parser_state.cur_character.name][ability] = location
				else:#Abilities
					if values.size()==0:
						err("Expected abilities, got nothing! '"+parts[1]+"'")
					var abilities_ar : Array[AbilityRef]
					for value in values:
						abilities_ar.push_back(mgsl.ability(value))
						
					mgsl.CHARACTERS[parser_state.cur_character.name].Abilities = abilities_ar									
			else:
				err("Expected character name or ability, got: '"+line+"'")


		Section.CONNECTIONS:
			# A connection looks like
			# TOWN <-> WELL
			# WELL -> HEAVE [ PIOUS ]
			# TOWN <-> WOODS [ SMALL or JUMP ]
			
			if line=="QUESTS":
				parser_state.section = Section.QUESTS
				return

			var arrow_type = "->"
			if line.find("<->") != -1:
				arrow_type = "<->"
			var parts = line.split(arrow_type)
			if parts.size() != 2:
				err("Expected 'A "+arrow_type+" B' format, got: '"+line+"'")
			var from : LocationRef = mgsl.location(parts[0].strip_edges())
			#do we have ability/character restrictions?
			var to_declaration = parts[1].strip_edges()
			var restrictions : Array[CharacterOrAbilityRef] = []
			var to:LocationRef
			if to_declaration.find("[") != -1:
				var declaration_parts = to_declaration.split("[")
				if declaration_parts.size() != 2:
					err("Expected 'A [ B ]' format, got: '"+to_declaration+"'")
				#require ] at the end, then delete it
				if declaration_parts[1].rfind("]") != declaration_parts[1].length()-1:
					err("Expected ']' at the end, got: '"+to_declaration+"'")
				declaration_parts[1] = declaration_parts[1].substr(0,declaration_parts[1].length()-1)

				to = mgsl.location(declaration_parts[0].strip_edges())
				var restrictions_parts = declaration_parts[1].strip_edges().split(" or ")
				for i in range(restrictions_parts.size()):
					var restriction : CharacterOrAbilityRef =  mgsl.character_or_ability(restrictions_parts[i].strip_edges())					
					restrictions.push_back(restriction)
			else:
				to = mgsl.location(to_declaration)
			
			
			var connection_dat:ConnectionDat = ConnectionDat.new(from,to,restrictions,cur_line)
			mgsl.CONNECTIONS.push_back(connection_dat)
			if arrow_type=="<->":
				mgsl.CONNECTIONS.push_back(connection_dat.flip())

		Section.QUESTS:
			# Quests look like the following:
			# BOY in WELL -> UNLOCK OBSERVER
			#
			# If there's a character in parentheticals before the requirement
			# ability, it's indicating that I believe only this character
			# can fulfil this requirement, to allow for sanity-checking later.
			# (OBSERVER) OPEN_DOOR in HOUSE -> FREE_PASSAGE_TO_AND_FROM TOWN
			var parts = line.split("->")
			if parts.size() != 2:
				err("Expected 'A -> B' format, got: '"+line+"'")
			var left_of_arrow:String = parts[0].strip_edges()
			var right_of_arrow:String = parts[1].strip_edges()
			var left_of_arrow_split_at_in = left_of_arrow.split(" in ")
			if left_of_arrow_split_at_in.size() != 2:
				err("Expected 'A in B' format, got: '"+left_of_arrow+"'")
			var location : LocationRef = mgsl.location(check_word(left_of_arrow_split_at_in[1]))
			if !mgsl.ENUMS.Location.has(location.name):
				err("Unknown location: '"+str(location)+"'")
			var left_of_in:String = left_of_arrow_split_at_in[0].strip_edges()
			
			# This can look like (CHARACTER) ABILITY or just ABILITY or CHARACTER
			# either way, parse left_of_in into a list of CharacterOrAbilityRef
			var dats : Array[CharacterOrAbilityRef] = []
			var brackets_present : bool = left_of_in.find("(") != -1
			left_of_in = left_of_in.replace("("," ").replace(")"," ")
			var left_of_in_parts = left_of_in.split(" ",false)
			for i in range(left_of_in_parts.size()):
				dats.push_back(mgsl.character_or_ability(left_of_in_parts[i]))
			if brackets_present:
				if dats.size() != 2:
					err("Expected 2 arguments, got: "+str(dats.size()))
			else:
				if dats.size() != 1:
					err("Expected 1 argument, got: "+str(dats.size()))

			var agent_spec:Quest_Agent_Spec = Quest_Agent_Spec.new( dats, mgsl.cur_line )			
			
			# to the right of the arrow is/are function call(s) of the form
			# UNLOCK OBSERVER
			# ADD_ABILITY BOY PIOUS
			# UNLOCK LION, UNLOCK MICE
			# ENDGAME
			# functions can be n-ary, with arguemnts separated by spaces
			var functions_toks = right_of_arrow.split(",")
			var functions : Array[FunctionDat] = []
			for i in range(functions_toks.size()):
				var function_args = functions_toks[i].strip_edges().split(" ")
				if function_args.size() == 0:
					err("Expected function name, got nothing! '"+str(functions[i])+"'")
				var function_name : String = check_word(function_args[0].strip_edges())
				
				function_args = function_args.slice(1)
				var function_args_typed:Array[LAC_Ref]
				for function_arg : String in function_args:
					function_args_typed.push_back(mgsl.LAC(function_arg))
					
				
				#	func _init(_name:String,quest_dat:QuestDat,_args:Array[LAC_Ref],state:StateDat):
				var function_dat : FunctionDat = FunctionDat.new(function_name,location,agent_spec,function_args_typed,mgsl)
				functions.push_back(function_dat)
			
			var quest_dat:QuestDat = QuestDat.new(agent_spec,location,functions,cur_line)	
			mgsl.QUESTS.push_back(quest_dat)
			
		_:
			err("Unknown parser state: '"+str(parser_state.section)+"'")
	
func expand_ability_hierarchy():
	# if we have
	# LONGJUMP > JUMP
	# then every character with LONGJUMP also has JUMP 
	# because of transitivity we'll loop through the list until there are no more changes to be made
	var changed = true
	while changed:
		changed=false
		for ability_inequality in self.mgsl.ABILITY_HIERARCHY:
			var greater = ability_inequality.greater
			var lesser = ability_inequality.lesser
			for character_type in self.mgsl.CHARACTERS:
				var character = self.mgsl.CHARACTERS[character_type]
				if character.has_ability(greater) && !character.has_ability(lesser):
					character.Abilities.push_back(lesser)
					changed=true
					#print("Added ",lesser," to ",character_type,"'s abilities because it has ",lesser)



#WHY DON'T THE MICE SEEM TO BE ABLE TO GET TO CHURCH_OUTER (they can't but it's not displayed!)

static func array_has(ar:Array,el:Variant)->bool:
	for a in ar:
		if a.name==el.name:
			return true
	return false

static func array_equals(ar1:Array,ar2:Array)->bool:
	if ar1.size()!=ar2.size():
		return false
	for i in range(ar1.size()):
		var e1=ar1[i]
		var e2=ar2[i]
		if e1.name!=e2.name:
			return false
	return true
	
func find_domain(character:CharacterRef)->Array:
	#for a given character, find all locations it can visit
	var character_dat : CharacterDat = self.mgsl.CHARACTERS[character.name]
	var domain : Array[LocationRef] = [ character_dat.Location ]


		
	#if not unlocked, return only the current location
	if !self.mgsl.is_char_unlocked(character):
		return domain
		
	var changed=true
	while changed:
		changed=false
		#try to go through all connections, to see if we can reach somewhere new
		for connection in self.mgsl.CONNECTIONS:
			var from : LocationRef = connection.from
			var to : LocationRef = connection.to
			var restrictions : Array[CharacterOrAbilityRef] = connection.restrictions

			if array_has(domain,from) && !array_has(domain,to):
				#check if we have the required abilities
				var can_go=restrictions.size()==0
				for restriction in restrictions:
					if array_has(character_dat.Abilities,restriction):
						can_go=true
						break
				if can_go:
					domain.push_back(to)
					changed=true
					#print("Added ",to," to ",str(character),"'s domain because of rule on line ",connection.line_number)
	
	return domain

func build_domain_dictionary() -> Dictionary[String,Array]: # [CharacterRef, Array[LocationRef]]
	var domain : Dictionary[String,Array] = {} # [CharacterRef, Array[LocationRef]]
	for character_name in self.mgsl.CHARACTERS:
		var character : CharacterRef = mgsl.character(character_name)
		domain[character.name] = find_domain(character)
	return domain

func build_location_occupancy() -> Dictionary[String,Array]: # [LocationRef, Array[CharacterRef]]
	# transpose the character_domains dictionary
	var loc_occupancy : Dictionary[String,Array ] = {} # [LocationRef, Array[CharacterRef]]
	#for each location, add an empty array
	for location in self.mgsl.ENUMS.Location:
		var lref : LocationRef = self.mgsl.location(location)
		loc_occupancy[lref.name] = []
	#add characters to their respective locations
	for character_ref_name : String in mgsl.character_domains:
		for lref : LocationRef in mgsl.character_domains[character_ref_name]:
			var character_ref : CharacterRef = self.mgsl.character(character_ref_name)
			loc_occupancy[lref.name].push_back(character_ref)
	return loc_occupancy

#gets connections IN BOTH DIRECTIONS. BUYER BEWARE
func get_connections_bidi(from:LocationRef,to:LocationRef)->Array[ConnectionDat]:
	var connections : Array[ConnectionDat] = []
	for connection in self.mgsl.CONNECTIONS:
		if (connection.from.equals(from) && connection.to.equals(to)) || (connection.from.equals(to) && connection.to.equals(from)):
			connections.push_back(connection)
	return connections

class ParserState:
	var section:Section
	var in_comments:bool
	var cur_enum_declaration:Variant
	var cur_character:CharacterRef
	func _init():
		section=Section.INITIAL
		in_comments=false
		
var cur_line:int=0;
func parse_lines(_lines)->StateDat:
	self.lines=_lines
	var parser_state : ParserState = ParserState.new()

	for i in range(lines.size()):
		cur_line=i
		mgsl.cur_line=i
		parse_line(parser_state,i,lines[i])

	var player_character : CharacterRef = mgsl.character(mgsl.ENUMS.Characters[0])
	mgsl.unlocked_characters = [player_character]
	return mgsl


func parse_string(s)->StateDat:
	return parse_lines(s.split("\n"))


#[CHILD]
#[ OBSERVER OPEN_DOOR ]
#[ HOUSE ]
#[ <null>, PALACE ]
#[ MEADOW ]
#[ CHURCH_INNER ]
#[ WELL ]
func simulate_step()->bool:
	# we go through all the rules, and check which ones might be applied.  
	# Because we are in automata-style simulation, we don't want to apply
	# the rules as we go, but rather all at once at the end, to avoid
	# chain reactions and have a simulation step actually represent a
	# single step (even if that invokes multiple characters doing things).

	mgsl.character_domains = build_domain_dictionary()
	mgsl.location_occupancy = build_location_occupancy()
	
	mgsl.actions_this_turn = []
	var rules_to_apply : Array[QuestDat] = []
	var questlist:Array[QuestDat]=self.mgsl.QUESTS
	for quest_i in range(questlist.size()-1,-1,-1):
		var quest:QuestDat =questlist[quest_i]
		var desired_ability_or_character : CharacterOrAbilityRef = quest.agent.restriction
		var location = quest.location
		var is_ability = desired_ability_or_character.is_ability
		var is_character = desired_ability_or_character.is_character
		if !is_ability && !is_character:
			err("Unknown ability or character: '"+str(desired_ability_or_character)+"'")
		
		var occupancy_untyped : Array = mgsl.location_occupancy[location.name]
		var occupancy : Array[CharacterRef] = []
		for o:CharacterRef in occupancy_untyped:
			occupancy.push_back(o)
			
		if is_character:
			# if the quest specifies a character, we need to check it's in this list
			if !array_has(occupancy,desired_ability_or_character):
				continue
		else: #is_ability
			# if the quest specifies an ability, we need to check that at least one character has it
			var found=false
			for character in occupancy:
				if !array_has(self.mgsl.unlocked_characters,character):
					continue
				if array_has(mgsl.CHARACTERS[character.name].Abilities,desired_ability_or_character):
					found=true
					break
			if !found:
				continue
				
		# so the quest can be applied
		rules_to_apply.push_back(quest)
		questlist.remove_at(quest_i)

	# now apply the rules
	for rule : QuestDat in rules_to_apply:
		for function : FunctionDat in rule.functions:
			var command = function.name
			match command:
				"UNLOCK":
					var character = function.args[0].get_character(rule.line_number)
					self.mgsl.unlocked_characters.push_back(character)
				"FREE_PASSAGE_TO_AND_FROM":
					var target_location = function.args[0].get_location(rule.line_number)
					var from_location = rule.location
					#remove all connections between these two locations, then add a blank one
					var connections = get_connections_bidi(from_location,target_location)
					for connection in connections:
						for oc_i:int in range(self.mgsl.CONNECTIONS.size()-1,-1,-1):
							var other_connection:ConnectionDat = mgsl.CONNECTIONS[oc_i]
							if other_connection.equals(connection):
								self.mgsl.CONNECTIONS.remove_at(oc_i)
					var new_connection : ConnectionDat = ConnectionDat.new(from_location,target_location,[],rule.line_number)
					self.mgsl.CONNECTIONS.push_back(new_connection)
					self.mgsl.CONNECTIONS.push_back(new_connection.flip())
				"ADD_ABILITY":
					var desired_agent : CharacterOrAbilityRef = rule.agent.restriction
					if !desired_agent.is_character:
						err("ADD_ABILITY requires a character, got: '"+str(desired_agent)+"'") 
					var character_ref : CharacterRef = desired_agent.get_character(rule.line_number)
					var ability_to_add : AbilityRef = function.args[0].get_ability()
					mgsl.CHARACTERS[character_ref.name].Abilities.push_back(ability_to_add)

	self.mgsl.actions_this_turn=rules_to_apply

	mgsl.character_domains = build_domain_dictionary()
	mgsl.location_occupancy = build_location_occupancy()

	return rules_to_apply.size() > 0
		
func simulate_game():
	playthrough=[]
	# I want to simulate the game until nothing more can be done

	mgsl.actions_this_turn = []
	playthrough.push_back(mgsl.copy())

	while simulate_step():
		print("simulating step")
		playthrough.push_back(mgsl.copy())
		
	print("simuilated ",playthrough.size()," steps")

func _init(s:String):
	alphanum.compile("[a-zA-Z0-9_]+")
	parse_string(s)
	#print(JSON.stringify(self.mgsl,"\t",false,true))
	expand_ability_hierarchy()

	
	mgsl.character_domains = build_domain_dictionary()
	mgsl.location_occupancy = build_location_occupancy()
	
	simulate_game()
	#mgsl.actions_this_turn=[]
	#self.playthrough=[mgsl]
	#
	#print(JSON.stringify(character_domains,"\t",false,true))
	
