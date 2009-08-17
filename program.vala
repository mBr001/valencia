/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

using Gee;

namespace Valencia {

public abstract class CompoundName : Object {
  public abstract string to_string();
}

public class SimpleName : CompoundName {
  public string name;
  
  public SimpleName(string name) { this.name = name; }
  
  public override string to_string() { return name; }
}

public class QualifiedName : CompoundName {
  public CompoundName basename;
  public string name;
  
  public QualifiedName(CompoundName basename, string name) {
      this.basename = basename;
      this.name = name;
  }
  
  public override string to_string() {
      return basename.to_string() + "." + name;
  }
}

public class SymbolSet : Object {
  HashSet<Symbol> symbols = new HashSet<Symbol>();
  string name;
  bool exact;
  bool type;
  bool constructor;

  SymbolSet(string name, bool type, bool exact, bool constructor) {
      this.name = name;
      this.type = type;
      this.exact = exact;
      this.constructor = constructor;
      
      // Since the set stores Symbols, but we actually want to hash their (name) strings, we must
      // provide custom hash and equality functions
      symbols.hash_func = Symbol.hash;
      symbols.equal_func = Symbol.equal;
  }

  void add_constructor(Symbol sym) {
      Class c = sym as Class;
      if (c != null) {
          if (exact) {
              Symbol? s = c.lookup_constructor();
              if (s != null)
                  symbols.add(s);
              else symbols.add(sym);
          } else {
              // Recursively add subclass constructors to the set
              foreach (Node n in c.members) {
                  Class subclass = n as Class;
                  if (subclass != null)
                      add_constructor(subclass);
                  else if (n is Constructor)
                      symbols.add((Symbol) n);
              }
          }
          // Recursively add subclass constructors to the set
      } else if (sym is Constructor) {
          symbols.add(sym);
      }
  }

  public bool add(Symbol sym) {
      if (sym.name == null)
          return false;

      if (exact) {
          if (sym.name != name)
              return false;
      } else if (!sym.name.has_prefix(name)) {
              return false;
      }

      if (type && sym as TypeSymbol == null)
          return false;

      if (constructor) {
          add_constructor(sym);
      // Don't add constructors to non-constructor sets
      } else if (!(sym is Constructor))
          symbols.add(sym);

      return exact;
  }

  // Convenience function for getting the first element without having to use iterators.
  // This is mostly for users expecting exact matches.
  public Symbol? first() {
      foreach (Symbol s in symbols)
          return s;
      return null;
  }

  public HashSet<Symbol>? get_symbols() {
      // It doesn't make sense to display the exact match of a partial search if there is only
      // one symbol found that matches perfectly 
      if (symbols.size == 0 || (symbols.size == 1 && !exact && first().name == name))
          return null;

      return symbols;
  }
  
  public string get_name() {
      return name;
  }
}

public abstract class Node : Object {
  public int start;
  public int end;

  Node(int start, int end) {
      this.start = start;
      this.end = end;
  }

  // Return all children which may possibly contain a scope.
  public virtual ArrayList<Node>? children() { return null; }
  
  protected static ArrayList<Node>? single_node(Node? n) {
      if (n == null)
          return null;
      ArrayList<Node> a = new ArrayList<Node>();
      a.add(n);
      return a;
  }
  
  public Chain? find(Chain? parent, int pos) {
      Chain c = parent;
      Scope s = this as Scope;
      if (s != null)
          c = new Chain(s, parent);    // link this scope in
          
      ArrayList<Node> nodes = children();
      if (nodes != null)
          foreach (Node n in nodes)
              if (n.start <= pos && pos <= n.end)
                  return n.find(c, pos);
      return c;
  }

  public static bool lookup_in_array(ArrayList<Node> a, SymbolSet symbols) {
      foreach (Node n in a) {
          Symbol s = n as Symbol;
          if (s != null && symbols.add(s))
              return true;
      }
      return false;
  }
  
  public abstract void print(int level);

  protected void do_print(int level, string s) {
      stdout.printf("%s%s\n", string.nfill(level * 2, ' '), s);
  }    
}

public abstract class Symbol : Node {
  public SourceFile source;
  public string name;        // symbol name, or null for a constructor
  
  public Symbol(string? name, SourceFile source, int start, int end) {
      base(start, end);
      this.source = source;
      this.name = name;
  }
  
  protected void print_name(int level, string s) {
      do_print(level, s + " " + name);
  }

  public static uint hash(void *item) {
      weak Symbol symbol = (Symbol) item;

      // Unnamed constructors always have null names, so hash their parent class' name
      if (symbol.name == null) {
          Constructor c = symbol as Constructor;
          assert(c != null);
          return c.parent.name.hash();
      } else
          return symbol.name.hash();
  }

  public static bool equal(void* a, void* b) {
      weak Symbol a_symbol = (Symbol) a;
      weak Symbol b_symbol = (Symbol) b;
      return a_symbol.name == b_symbol.name;
  }
}

public interface Scope : Object {
  // Adds all members not past the position specified by 'pos' inside this scope to 'symbols'
  // (members meaning fields, methods, classes, enums, etc...)
  public abstract bool lookup(SymbolSet symbols, int pos);
}

public abstract class TypeSymbol : Symbol {
  public TypeSymbol(string? name, SourceFile source, int start, int end) {
      base(name, source, start, end);
  }
}

public abstract class Statement : Node {
  public Statement(int start, int end) { base(start, end); }
  
  public virtual bool defines_symbol(SymbolSet symbols) { return false; }
}

public abstract class Variable : Symbol {
  public CompoundName type;
  
  public Variable(CompoundName type, string name, SourceFile source, int start, int end) {
      base(name, source, start, end);
      this.type = type;
  }
  
  protected abstract string kind();
  
  public override void print(int level) {
      print_name(level, kind() + " " + type.to_string());
  }
}

public class LocalVariable : Variable {
  public LocalVariable(CompoundName type, string name, SourceFile source, int start, int end) {
      base(type, name, source, start, end);
  }
  
  protected override string kind() { return "local"; }
}

public class DeclarationStatement : Statement {
  public ArrayList<LocalVariable> variables;
  
  public DeclarationStatement(ArrayList<LocalVariable> variables, int start, int end) {
      base(start, end);
      this.variables = variables;
  }

  public override bool defines_symbol(SymbolSet symbols) {
      foreach (LocalVariable variable in variables)
          if (symbols.add(variable))
              return true;
      return false;
  }
  
  public override void print(int level) {
      foreach (LocalVariable variable in variables)
          variable.print(level);
  }
}

public class ForEach : Statement, Scope {
  public LocalVariable variable;
  public Statement statement;
  
  public ForEach(LocalVariable variable, Statement? statement, int start, int end) {
      base(start, end);
      this.variable = variable;
      this.statement = statement;
  }
  
  public override ArrayList<Node>? children() { return single_node(statement); }
  
  bool lookup(SymbolSet symbols, int pos) {
      return symbols.add(variable);
  }    
  
  protected override void print(int level) {
      do_print(level, "foreach");
      
      variable.print(level + 1);
      if (statement != null)
          statement.print(level + 1);
  }
}

public class Chain : Object {
  Scope scope;
  Chain parent;
  
  public Chain(Scope scope, Chain? parent) {
      this.scope = scope;
      this.parent = parent;
  }
  
  public void lookup(SymbolSet symbols, int pos) {
      if (scope.lookup(symbols, pos))
          return;

      if (parent != null)
          parent.lookup(symbols, pos);
  }
}

public class Block : Statement, Scope {
  public ArrayList<Statement> statements = new ArrayList<Statement>();

  public override ArrayList<Node>? children() { return statements; }
  
  bool lookup(SymbolSet symbols, int pos) {
      foreach (Statement s in statements) {
          if (s.start > pos)
              return false;
          if (s.defines_symbol(symbols))
              return true;
      }
      return false;
  }
  
  protected override void print(int level) {
      do_print(level, "block");
      
      foreach (Statement s in statements)
          s.print(level + 1);
  }
}

public class Parameter : Variable {
  public Parameter(CompoundName type, string name, SourceFile source, int start, int end) {
      base(type, name, source, start, end);
  }
  
  protected override string kind() { return "parameter"; }
}

// a construct block
public class Construct : Node {
  public Block body;
  
  public Construct(Block body, int start, int end) {
      base(start, end);
      this.body = body;
  }
  
  public override ArrayList<Node>? children() {
      return single_node(body);
  }

  public override void print(int level) {
      do_print(level, "construct");
      if (body != null)
          body.print(level + 1);
  }
}

public class Method : Symbol, Scope {
  public ArrayList<Parameter> parameters = new ArrayList<Parameter>();
  public Block body;
  string prototype = "";
  
  public Method(string? name, SourceFile source) { 
      base(name, source, 0, 0); 
  }
  
  public override ArrayList<Node>? children() { return single_node(body);    }
  bool lookup(SymbolSet symbols, int pos) {
      return Node.lookup_in_array(parameters, symbols);
  }
  
  protected virtual void print_type(int level) {
      print_name(level, "method");
  }
  
  public override void print(int level) {
      print_type(level);
      
      foreach (Parameter p in parameters)
          p.print(level + 1);
      if (body != null)
          body.print(level + 1);
  }
  
  public void update_prototype(string proto) {
      prototype = proto;
      prototype.chomp();

      // Clean up newlines and remove extra spaces
      if (prototype.contains("\n")) {
          string[] split_lines = prototype.split("\n");
          prototype = "";
          for (int i = 0; split_lines[i] != null; ++i) {
              weak string str = split_lines[i];
              str.strip();
              prototype += str;
              if (split_lines[i + 1] != null)
                  prototype += " ";
          }
      }
  }
  
  public string to_string() {
      return prototype;
  }
  
}

public class Constructor : Method {
  public weak Class parent;

  public Constructor(string? unqualified_name, Class parent, SourceFile source) { 
      base(unqualified_name, source); 
      this.parent = parent;
  }
  
  public override void print_type(int level) {
      do_print(level, "constructor");
  }
}

public class Field : Variable {
  public Field(CompoundName type, string name, SourceFile source, int start, int end) {
      base(type, name, source, start, end);
  }
  
  protected override string kind() { return "field"; }
}

public class Property : Variable {
  // A Block containing property getters and/or setters.
  public Block body;

  public Property(CompoundName type, string name, SourceFile source, int start, int end) {
      base(type, name, source, start, end);
  }
  
  public override ArrayList<Node>? children() {
      return single_node(body);
  }

  protected override string kind() { return "property"; }

  public override void print(int level) {
      base.print(level);
      body.print(level + 1);
  }
}

// a class, struct, interface or enum
public class Class : TypeSymbol, Scope {
  public ArrayList<CompoundName> super = new ArrayList<CompoundName>();
  public ArrayList<Node> members = new ArrayList<Node>();
  weak Class enclosing_class;

  public Class(string name, SourceFile source, Class? enclosing_class) {
      base(name, source, 0, 0); 
      this.enclosing_class = enclosing_class;
  }
  
  public override ArrayList<Node>? children() { return members; }
  
  public Symbol? lookup_constructor() {
      foreach (Node n in members) {
          Constructor c = n as Constructor;
          // Don't accept named constructors
          if (c != null && c.name == null) {
              return (Symbol) c;
          }
      }
      return null;
  }
  
  bool lookup1(SymbolSet symbols, HashSet<Class> seen) {
      if (Node.lookup_in_array(members, symbols))
          return true;

      // Make sure we don't run into an infinite loop if a user makes this mistake:
      // class Foo : Foo { ...
      seen.add(this);

      // look in superclasses        
      foreach (CompoundName s in super) {
          // We look up the parent class in the scope at (start - 1); that excludes
          // this class itself (but will include the containing sourcefile,
          // even if start == 0.)
          SymbolSet class_set = source.resolve_type(s, start - 1);
          Class c = class_set.first() as Class;

          if (c != null && !seen.contains(c)) {
              if (c.lookup1(symbols, seen))
                  return true;
          }
      }
      return false;
      
  }    
  
  bool lookup(SymbolSet symbols, int pos) {
      return lookup1(symbols, new HashSet<Class>());
  }
  
  public override void print(int level) {
      StringBuilder sb = new StringBuilder();
      sb.append("class " + name);
      for (int i = 0 ; i < super.size ; ++i) {
          sb.append(i == 0 ? " : " : ", ");
          sb.append(super.get(i).to_string());
      }
      do_print(level, sb.str);
      
      foreach (Node n in members)
          n.print(level + 1);
  }

  public string to_string() {
      return (enclosing_class != null) ? enclosing_class.to_string() + "." + name : name;
  }

}

// A Namespace is a TypeSymbol since namespaces can be used in type names.
public class Namespace : TypeSymbol, Scope {
  public string full_name;
  
  public Namespace(string? name, string? full_name, SourceFile source) {
      base(name, source, 0, 0);
      this.full_name = full_name;
  }
  
  public ArrayList<Symbol> symbols = new ArrayList<Symbol>();
  
  public override ArrayList<Node>? children() { return symbols; }

  public bool lookup(SymbolSet symbols, int pos) {
      return source.program.lookup_in_namespace(full_name, symbols);
  }
  
  public bool lookup1(SymbolSet symbols) {
      return Node.lookup_in_array(this.symbols, symbols);
  }

  public override void print(int level) {
      print_name(level, "namespace");
      foreach (Symbol s in symbols)
          s.print(level + 1);
  }
}

public class SourceFile : Node, Scope {
  public weak Program program;
  public string filename;
  
  ArrayList<string> using_namespaces = new ArrayList<string>();
  public ArrayList<Namespace> namespaces = new ArrayList<Namespace>();
  public Namespace top;
  
  public SourceFile(Program? program, string filename) {
      this.program = program;
      this.filename = filename;
      alloc_top();
  }

  void alloc_top() {
      top = new Namespace(null, null, this);
      namespaces.add(top);
      using_namespaces.add("GLib");
  }

  public void clear() {
      using_namespaces.clear();
      namespaces.clear();
      alloc_top();
  }

  public override ArrayList<Node>? children() { return single_node(top);    }

  public void add_using_namespace(string name) {
      // Make sure there isn't a duplicate, since GLib is always added
      if (name == "GLib")
          return;
      using_namespaces.add(name);
  }

  bool lookup(SymbolSet symbols, int pos) {
      foreach (string ns in using_namespaces) {
          if (program.lookup_in_namespace(ns, symbols))
              return true;
      }
      return false;
  }

  public bool lookup_in_namespace(string? namespace_name, SymbolSet symbols) {
      foreach (Namespace n in namespaces)
          if (n.full_name == namespace_name) {
              if (n.lookup1(symbols))
                  return true;
          }
      return false;
  }

  public SymbolSet resolve1(CompoundName name, Chain chain, int pos, bool find_type, bool exact, 
                            bool constructor) {
      SimpleName s = name as SimpleName;
      if (s != null) {
          SymbolSet symbols = new SymbolSet(s.name, find_type, exact, constructor);
          chain.lookup(symbols, pos);
          return symbols;
      }

      // The basename of a qualified name is always going to be an exact match, and never a
      // constructor
      QualifiedName q = (QualifiedName) name;
      SymbolSet left_set = resolve1(q.basename, chain, pos, find_type, true, false);
      Symbol left = left_set.first();
      if (!find_type) {
          Variable v = left as Variable;
          if (v != null) {
              left_set = v.source.resolve_type(v.type, v.start);
              left = left_set.first();
          }
      }
      Scope scope = left as Scope;

      // It doesn't make sense to be looking up members of a method as a qualified name
      if (scope is Method)
          return new SymbolSet("", false, false, false);
      
      SymbolSet symbols = new SymbolSet(q.name, find_type, exact, constructor);
      if (scope != null)
          scope.lookup(symbols, 0);
      
      return symbols;
  }

  public Symbol? resolve(CompoundName name, int pos, bool constructor) {
      SymbolSet symbols = resolve1(name, find(null, pos), pos, false, true, constructor);
      return symbols.first();
  }    
  
  public SymbolSet resolve_type(CompoundName type, int pos) {
      return resolve1(type, find(null, pos), 0, true, true, false);
  }

  public SymbolSet resolve_prefix(CompoundName prefix, int pos, bool constructor) {
      return resolve1(prefix, find(null, pos), pos, false, false, constructor);
  }
  
  public override void print(int level) {
      top.print(level);
  }
}

public class ErrorInfo : Object {
  public string filename;
  public string start_line;
  public string start_char;
  public string end_line;
  public string end_char;
}

public class ErrorPair : Object {
  public Gtk.TextMark document_pane_error;
  public Gtk.TextMark build_pane_error;
  public ErrorInfo error_info;
  
  public ErrorPair(Gtk.TextMark document_err, Gtk.TextMark build_err, ErrorInfo err_info) {
      document_pane_error = document_err;
      build_pane_error = build_err;
      error_info = err_info;
  }
}

public class ErrorList : Object {
  public Gee.ArrayList<ErrorPair> errors;
  public int error_index;
  
  public ErrorList() {
      errors = new Gee.ArrayList<ErrorPair>();
      error_index = -1;    
  }
}

public class Makefile : Object {
  public string path;
  public string relative_binary_run_path;
  
  bool regex_parse(GLib.DataInputStream datastream) {
      Regex program_regex, rule_regex, root_regex;
      try {            
          root_regex = new Regex("""^\s*BUILD_ROOT\s*=\s*1\s*$""");
          program_regex = new Regex("""^\s*PROGRAM\s*=\s*(\S+)\s*$""");
          rule_regex = new Regex("""^ *([^: ]+) *:""");
      } catch (RegexError e) {
          GLib.warning("A RegexError occured when creating a new regular expression.\n");
          return false;        // TODO: report error
      }

      bool rule_matched = false;
      bool program_matched = false;
      bool root_matched = false;
      MatchInfo info;

      // this line is necessary because of a vala compiler bug that thinks info is uninitialized
      // within the block: if (!program_matched && program_regex.match(line, 0, out info)) {
      program_regex.match(" ", 0, out info);
          
      while (true) {
          size_t length;
          string line;
         
          try {
              line = datastream.read_line(out length, null);
          } catch (GLib.Error err) {
              GLib.warning("An unexpected error occurred while parsing the Makefile.\n");
              return false;
          }
          
          // The end of the document was reached, ending...
          if (line == null)
              break;
          
          if (!program_matched && program_regex.match(line, 0, out info)) {
              // The 'PROGRAM = xyz' regex can be matched anywhere in the makefile, where the rule
              // regex can only be matched the first time.
              relative_binary_run_path = info.fetch(1);
              program_matched = true;
          } else if (!rule_matched && !program_matched && rule_regex.match(line, 0, out info)) {
              rule_matched = true;
              relative_binary_run_path = info.fetch(1);
          } else if (!root_matched && root_regex.match(line, 0, out info)) {
              root_matched = true;
          }

          if (program_matched && root_matched)
              break;
      }
      
      return root_matched;
  }
  
  // Return: true if current directory will be root, false if not
  public bool parse(GLib.File makefile) {
      GLib.FileInputStream stream;
      try {
          stream = makefile.read(null);
       } catch (GLib.Error err) {
          GLib.warning("Unable to open %s for parsing.\n", path);
          return false;
       }
      GLib.DataInputStream datastream = new GLib.DataInputStream(stream);
      
      return regex_parse(datastream);
  }

  public void reparse() {
      if (path == null)
          return;
          
      GLib.File makefile = GLib.File.new_for_path(path);
      parse(makefile);
  }
  
  public void reset_paths() {
      path = null;
      relative_binary_run_path = null;
  }

}

public class Program : Object {
  public ErrorList error_list;

  string top_directory;
  
  int total_filesize;
  int parse_list_index;
  ArrayList<string> sourcefile_paths = new ArrayList<string>();
  bool parsing;
  
  ArrayList<SourceFile> sources = new ArrayList<SourceFile>();
  static ArrayList<SourceFile> system_sources = new ArrayList<SourceFile>();
  
  static ArrayList<Program> programs;
  
  Makefile makefile;

  bool recursive_project;
  
  signal void local_parse_complete();
  public signal void system_parse_complete();
  public signal void parsed_file(double fractional_progress);

  Program(string directory) {
      error_list = null;
      top_directory = null;
      parsing = true;
      makefile = new Makefile();
      
      // Search for the program's makefile; if the top_directory still hasn't been modified
      // (meaning no makefile at all has been found), then just set it to the default directory
      File makefile_dir = File.new_for_path(directory);
      if (get_makefile_directory(makefile_dir)) {
          recursive_project = true;
      } else {
          // If no root directory was found, make sure there is a local top directory, and 
          // scan only that directory for sources
          top_directory = directory;
          recursive_project = false;
      }

      GLib.Idle.add(parse_local_vala_files_idle_callback);
      
      programs.add(this);
  }

  // Returns true if a BUILD_ROOT or configure.ac was found: files should be found recursively
  // False if only the local directory will be used
  bool get_makefile_directory(GLib.File makefile_dir) {
      if (configure_exists_in_directory(makefile_dir))
          return true;
  
      GLib.File makefile_file = makefile_dir.get_child("Makefile");
      if (!makefile_file.query_exists(null)) {
          makefile_file = makefile_dir.get_child("makefile");
          
          if (!makefile_file.query_exists(null)) {
              makefile_file = makefile_dir.get_child("GNUmakefile");
              
              if (!makefile_file.query_exists(null)) {
                  return goto_parent_directory(makefile_dir);
              }
          }
      }

      // Set the top_directory to be the first BUILD_ROOT we come across
      if (makefile.parse(makefile_file)) {
          set_paths(makefile_file);
          return true;
      }
      
      return goto_parent_directory(makefile_dir);
  }
  
  bool goto_parent_directory(GLib.File base_directory) {
      GLib.File parent_dir = base_directory.get_parent();
      return parent_dir != null && get_makefile_directory(parent_dir);
  }
  
  bool configure_exists_in_directory(GLib.File configure_dir) {
      GLib.File configure = configure_dir.get_child("configure.ac");
      
      if (!configure.query_exists(null)) {
          configure = configure_dir.get_child("configure.in");
  
          if (!configure.query_exists(null))
              return false;
      }

      // If there's a configure file, don't bother parsing for a makefile        
      top_directory = configure_dir.get_path();
      makefile.reset_paths();

      return true;
  }

  void set_paths(GLib.File makefile_file) {
      makefile.path = makefile_file.get_path();
      top_directory = Path.get_dirname(makefile.path);
  }

  string get_system_vapi_directory() {
      // Sort of a hack to get the path to the system vapi file directory. Gedit may hang or 
      // crash if the vala compiler .so is not present...
      string[] null_dirs = {};
      Vala.CodeContext context = new Vala.CodeContext();
      string path = context.get_package_path("gobject-2.0", null_dirs);
      return Path.get_dirname(path);
  }
  
  void finish_local_parse() {
      parsing = false;
      local_parse_complete();
      // Emit this now, otherwise it will never be emitted, since the system parsing is done
      if (system_sources.size > 0)
          system_parse_complete();
  }

  bool parse_local_vala_files_idle_callback() {
      if (sourcefile_paths.size == 0) {
          // Don't parse system files locally!
          string system_directory = get_system_vapi_directory();
          if (top_directory == system_directory || 
              (recursive_project && dir_has_parent(system_directory, top_directory))) {
              finish_local_parse();
              return false;
          }
          
          cache_source_paths_in_directory(top_directory, recursive_project);
      }

      // We can reasonably parse 3 files in one go to take a load off of X11
      for (int i = 0; i < 3; ++i) {
          if (!parse_vala_file(sources)) {
              finish_local_parse();
              return false;                
          }
      }
      
      return true;
  }

  bool parse_system_vala_files_idle_callback() {
      if (sourcefile_paths.size == 0) {
          string system_directory = get_system_vapi_directory();
          cache_source_paths_in_directory(system_directory, true);
      }

      for (int i = 0; i < 3; ++i) {
          if (!parse_vala_file(system_sources)) {
              parsing = false;
              system_parse_complete();
              return false;
          }
      }

      return true;
  }

  // Takes the next vala file in the sources path list and parses it. Returns true if there are
  // more files to parse, false if there are not.
  bool parse_vala_file(ArrayList<SourceFile> source_list) {
      if (sourcefile_paths.size == 0) {
          return false;
	  }
	
      string path = sourcefile_paths.get(parse_list_index);

      // The index is incremented here because if an error happens, we want to skip this file
      // next time around
      ++parse_list_index;        
      
      SourceFile source = new SourceFile(this, path);
      string contents;
      
      try {
          FileUtils.get_contents(path, out contents);
      } catch (GLib.FileError e) {
          // needs a message box? stderr.printf message?
          return parse_list_index == sourcefile_paths.size;
      }

      Parser parser = new Parser();
      parser.parse(source, contents);
      source_list.add(source);
      // Only show parsing progress if the filesize is over 1MB (1048576 bytes == 1 megabyte)
      if (total_filesize > 1048576)
          parsed_file((double) (parse_list_index) / sourcefile_paths.size);
      
      return parse_list_index != sourcefile_paths.size;
  }

  // returns the total size of the files
  int cache_source_paths_in_directory(string directory, bool recursive) {
      parse_list_index = 0;
      
      Dir dir;
      try {
          dir = Dir.open(directory);
      } catch (GLib.FileError e) {
          GLib.warning("Error opening directory: %s\n", directory);
          return 0;
      }
      
      total_filesize = 0;
      
      while (true) {
          string file = dir.read_name();

          if (file == null)
              break;

          // doesn't parse posix files to avoid built-in type vala profile conflicts (posix.vapi
          // contains definitions for 'int', jumping to definition may open posix.vapi instead
          // of glib.vapi            
          if (file == "posix.vapi") 
              continue;

          string path = Path.build_filename(directory, file);

          if (is_vala(file)) {
              sourcefile_paths.add(path);
              
              try {
              GLib.File sourcefile = GLib.File.new_for_path(path);
              GLib.FileInfo info = sourcefile.query_info("standard::size", 
                                                         GLib.FileQueryInfoFlags.NONE, null);
              total_filesize += (int) info.get_size();
              } catch (GLib.Error e) {
              }
          }
          else if (recursive && GLib.FileUtils.test(path, GLib.FileTest.IS_DIR))
              total_filesize += cache_source_paths_in_directory(path, true);
      }
      
      return total_filesize;
  }
  
  void parse_system_vapi_files() {
      // Don't parse system vapi files twice
      if (system_sources.size > 0)
          return;

      // Only begin parsing vapi files after the local vapi files have been parsed        
      if (is_parsing()) {
          local_parse_complete += parse_system_vapi_files;
      } else {
          parsing = true;
          parse_list_index = 0;
          sourcefile_paths.clear();
          GLib.Idle.add(this.parse_system_vala_files_idle_callback);
      }
  }
  
  public static bool is_vala(string filename) {
      return filename.has_suffix(".vala") ||
             filename.has_suffix(".vapi") ||
             filename.has_suffix(".cs");    // C#
  }

  public bool lookup_in_namespace1(ArrayList<SourceFile> source_list, string? namespace_name, 
                                      SymbolSet symbols, bool vapi) {
      foreach (SourceFile source in source_list)
          if (source.filename.has_suffix(".vapi") == vapi) {
              if (source.lookup_in_namespace(namespace_name, symbols))
                  return true;
          }
      return false;
  }

  public bool lookup_in_namespace(string? namespace_name, SymbolSet symbols) {
      // First look in non-vapi files; we'd like definitions here to have precedence.
      if (!lookup_in_namespace1(sources, namespace_name, symbols, false))
          if (!lookup_in_namespace1(sources, namespace_name, symbols, true)); // .vapi files
              if (!lookup_in_namespace1(system_sources, namespace_name, symbols, true))
                  return false;
      return true;
  }    

  SourceFile? find_source1(string path, ArrayList<SourceFile> source_list) {
      foreach (SourceFile source in source_list) {
          if (source.filename == path)
              return source;
      }
      return null;
  }

  public SourceFile? find_source(string path) {
      SourceFile sf = find_source1(path, sources);
      if (sf == null)
          sf = find_source1(path, system_sources);

      return sf;
  }
  
  // Update the text of a (possibly new) source file in this program.
  void update1(string path, string contents) {
      SourceFile source = find_source(path);
      if (source == null) {
          source = new SourceFile(this, path);
          sources.add(source);
      } else source.clear();
      new Parser().parse(source, contents);
  }
  
  public void update(string path, string contents) {
      if (!is_vala(path))
          return;
          
      if (recursive_project && dir_has_parent(path, top_directory)) {
          update1(path, contents);
          return;
      }
      
      string path_dir = Path.get_dirname(path);    
      if (top_directory == path_dir)
          update1(path, contents);
  }
  
  static Program? find_program(string dir) {
      if (programs == null)
          programs = new ArrayList<Program>();
          
      foreach (Program p in programs) {
          if (p.recursive_project && dir_has_parent(dir, p.get_top_directory()))
              return p;
          else if (p.top_directory == dir)
              return p;
      }
      return null;
  }
  
  public static Program find_containing(string path, bool parse_system_vapi = false) {
      string dir = Path.get_dirname(path);
      Program p = find_program(dir);
      
      if (parse_system_vapi) {
          if (p == null)
              p = new Program(dir);
          p.parse_system_vapi_files();
      }
      
      return (p != null) ? p : new Program(dir);
  }
  
  public static Program? null_find_containing(string? path) {
      if (path == null)
          return null;
      string dir = Path.get_dirname(path);
      return find_program(dir);    
  }

  // Update the text of a (possibly new) source file in any existing program.
  // If (contents) is null, we read the file's contents from disk.
  public static void update_any(string path, string? contents) {
      if (!is_vala(path))
          return;
        
        // If no program exists for this file, don't even bother looking
      string dir = Path.get_dirname(path);
        if (find_program(dir) == null)
            return;
        
      string contents1;        // owning variable
      if (contents == null) {
          try {
              FileUtils.get_contents(path, out contents1);
          } catch (FileError e) { 
              GLib.warning("Unable to open %s for updating\n", path);
              return; 
          }
          contents = contents1;
      }

      // Make sure to update the file for each sourcefile
      foreach (Program program in programs) {
          SourceFile sf = program.find_source(path);
              if (sf != null)
                  program.update1(path, contents);
      }
  }

  public static void rescan_build_root(string sourcefile_path) {
      Program? program = find_program(Path.get_dirname(sourcefile_path));
      
      if (program == null)
          return;

      File current_dir = File.new_for_path(Path.get_dirname(sourcefile_path));        
      string old_top_directory = program.top_directory;
      string local_directory = current_dir.get_path();

      // get_makefile_directory will set top_directory to the path of the makefile it found - 
      // if the path is the same as the old top_directory, then no changes have been made
      bool found_root = program.get_makefile_directory(current_dir);

      // If a root was found and the new and old directories are the same, the old root was found:
      // nothing changes.
      if (found_root && old_top_directory == program.top_directory)
          return;
      if (!found_root && old_top_directory == local_directory)
          return;

      // If a new root was found, get_makefile_directory() will have changed program.top_directory
      // already; if not, then we need to set it to the local directory manually
      if (!found_root)
          program.top_directory = local_directory;

      // The build root has changed, so: 
      // 1) delete the old root
      assert(programs.size > 0);
      programs.remove(program);

       // 2) delete a program rooted at the new directory if one exists
      foreach (Program p in programs)
          if (p.top_directory == program.top_directory)
              programs.remove(p);
          
       // 3) create a new program at new build root
      new Program(program.top_directory);
  }    
  
  public string get_top_directory() {
      return top_directory;
  }

  public string? get_binary_run_path() {
      if (makefile.relative_binary_run_path == null)
          return null;
      return Path.build_filename(top_directory, makefile.relative_binary_run_path);
  }
  
  public bool get_binary_is_executable() {
      string? binary_path = get_binary_run_path();
      return binary_path != null && !binary_path.has_suffix(".so");
  }
  
  public void reparse_makefile() {
      makefile.reparse();
  }

  // Tries to find a full path for a filename that may be a sourcefile (or another file that
  // happens to reside in a sourcefile directory, like a generated .c file)
  public string? get_path_for_filename(string filename) {
      if (Path.is_absolute(filename))
          return filename;

      // Make sure the whole basename is matched, not just part of it            
      string relative_path = (filename.contains("/")) ? filename : "/" + filename;
      
      // Search for the best partial match possible
      foreach (SourceFile sf in sources) {
          if (sf.filename.has_suffix(relative_path))
              return sf.filename;
      }

      // If no direct match could be made, try searching all directories that the source files
      // are in for a file that matches the basename
      string basename = Path.get_basename(filename);
      Gee.ArrayList<string> dirs = new ArrayList<string>();
      foreach (SourceFile sf in sources) {
          string dir = Path.get_dirname(sf.filename);
          if (!dirs.contains(dir))
              dirs.add(dir);
      }
      foreach (string dir_str in dirs) {
          Dir directory;
          try {
              directory = Dir.open(dir_str);
          } catch (GLib.FileError e) {
              GLib.warning("Could not open %s for reading.\n", dir_str);
              return null;
          }
          string file = directory.read_name();
          while(file != null) {
              if (basename == file)
                  return Path.build_filename(dir_str, file);
              file = directory.read_name();
          }
      }
      
      return null;
  }

  public bool is_parsing() {
      return parsing;
  }
  
}

}

