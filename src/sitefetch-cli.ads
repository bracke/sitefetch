with Ada.Strings.Unbounded;

package Sitefetch.CLI is
   type Parse_Status is
     (Parse_Ok,
      Parse_Show_Help,
      Parse_Show_Version,
      Parse_Error);

   type Argument_Array is array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;

   type Parsed_Options is record
      Status           : Parse_Status := Parse_Error;
      Quiet            : Boolean := False;
      Verbose          : Boolean := False;
      JSONL_Output     : Boolean := False;
      JSON_Summary     : Boolean := False;
      Locale_Provided  : Boolean := False;
      Locale           : Ada.Strings.Unbounded.Unbounded_String;
      Limits           : Sitefetch.Fetch_Options := Sitefetch.Default_Fetch_Options;
      Source_URL       : Ada.Strings.Unbounded.Unbounded_String;
      Target_Directory : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String (".");
      Error_Key        : Ada.Strings.Unbounded.Unbounded_String;
      Error_Arg_Key    : Ada.Strings.Unbounded.Unbounded_String;
      Error_Arg_Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Parse command-line arguments supplied by the caller.
   --
   --  @param Arguments Command-line arguments excluding the executable name.
   --  @return Parsed options, help/version request, or deterministic error metadata.
   function Parse (Arguments : Argument_Array) return Parsed_Options
     with SPARK_Mode => On;

   --  Parse the current process command line.
   --
   --  @return Parsed options, help/version request, or deterministic error metadata.
   function Parse_Command_Line return Parsed_Options;
end Sitefetch.CLI;
