with Ada.Command_Line;
with Ada.Strings.Unbounded;

package body Sitefetch.CLI is
   use Ada.Strings.Unbounded;

   function Starts_With (Item : String; Prefix : String) return Boolean
     with SPARK_Mode => On
   is
   begin
      return Item'Length >= Prefix'Length
        and then Item (Item'First .. Item'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Starts_With_Dash (Item : String) return Boolean
     with SPARK_Mode => On
   is
   begin
      return Item'Length > 0 and then Item (Item'First) = '-';
   end Starts_With_Dash;

   type Natural_Parse_Result is record
      Valid : Boolean := False;
      Value : Natural := 0;
   end record;

   function Natural_Value (Text : String) return Natural_Parse_Result
     with SPARK_Mode => On
   is
      Result : Natural_Parse_Result;
   begin
      if Text = "" then
         return Result;
      end if;

      for Ch of Text loop
         if Ch not in '0' .. '9' then
            return (Valid => False, Value => 0);
         elsif Result.Value > (Natural'Last - Character'Pos (Ch) + Character'Pos ('0')) / 10 then
            return (Valid => False, Value => 0);
         end if;

         Result.Value := Result.Value * 10 + Character'Pos (Ch) - Character'Pos ('0');
      end loop;

      Result.Valid := True;
      return Result;
   end Natural_Value;

   procedure Set_Error
     (Options   : in out Parsed_Options;
      Key       : String;
      Arg_Key   : String := "";
      Arg_Value : String := "")
     with SPARK_Mode => On
   is
   begin
      Options.Status := Parse_Error;
      Options.Error_Key := To_Unbounded_String (Key);
      Options.Error_Arg_Key := To_Unbounded_String (Arg_Key);
      Options.Error_Arg_Value := To_Unbounded_String (Arg_Value);
   end Set_Error;

   procedure Set_Limit
     (Options : in out Parsed_Options;
      Name    : String;
      Text    : String;
      Failed  : out Boolean)
     with SPARK_Mode => On
   is
      Parsed : constant Natural_Parse_Result := Natural_Value (Text);
      Value  : constant Natural := Parsed.Value;
   begin
      if not Parsed.Valid then
         Set_Error (Options, "error.unknown_option", "option", Name);
         Failed := True;
      else
         Failed := False;
         if Name = "--max-pages" then
            Options.Limits.Crawl.Max_Pages := Value;
         elsif Name = "--max-depth" then
            Options.Limits.Crawl.Max_Depth := Value;
         elsif Name = "--max-bytes" then
            Options.Limits.Crawl.Max_Bytes := Value;
         elsif Name = "--max-failures" then
            Options.Limits.Crawl.Max_Failures := Value;
         elsif Name = "--retries" then
            Options.Limits.HTTP.Max_Retries := Value;
         elsif Name = "--retry-delay-ms" then
            Options.Limits.HTTP.Retry_Delay_MS := Value;
         elsif Name = "--retry-jitter-ms" then
            Options.Limits.HTTP.Retry_Jitter_MS := Value;
         elsif Name = "--request-delay-ms" then
            Options.Limits.HTTP.Request_Delay_MS := Value;
         elsif Name = "--cache-max-stale-ms" then
            Options.Limits.Cache.Max_Stale_MS := Value;
         elsif Name = "--max-per-host" then
            if Value > Sitefetch.Max_Worker_Count then
               Set_Error (Options, "error.unknown_option", "option", Name);
               Failed := True;
            else
               Options.Limits.Crawl.Max_Per_Host_Connections := Value;
            end if;
         elsif Name = "--workers" then
            if Value = 0 or else Value > Sitefetch.Max_Worker_Count then
               Set_Error (Options, "error.unknown_option", "option", Name);
               Failed := True;
            else
               Options.Limits.Crawl.Workers := Positive (Value);
            end if;
         end if;
      end if;
   end Set_Limit;

   procedure Set_Head_Policy
     (Options : in out Parsed_Options;
      Text    : String;
      Failed  : out Boolean)
     with SPARK_Mode => On
   is
   begin
      Failed := False;
      if Text = "always" or else Text = "page-like" then
         Options.Limits.HTTP.Head := Sitefetch.Head_Page_Like;
      elsif Text = "ambiguous" or else Text = "ambiguous-only" then
         Options.Limits.HTTP.Head := Sitefetch.Head_Ambiguous_Only;
      elsif Text = "off" or else Text = "disabled" or else Text = "none" then
         Options.Limits.HTTP.Head := Sitefetch.Head_Disabled;
      else
         Set_Error (Options, "error.unknown_option", "option", "--head");
         Failed := True;
      end if;
   end Set_Head_Policy;

   procedure Set_Cache_Mode
     (Options : in out Parsed_Options;
      Text    : String;
      Failed  : out Boolean)
     with SPARK_Mode => On
   is
   begin
      Failed := False;
      if Text = "ignore" or else Text = "off" or else Text = "none" then
         Options.Limits.Cache.Mode := Sitefetch.Cache_Ignore;
      elsif Text = "revalidate" or else Text = "incremental" then
         Options.Limits.Cache.Mode := Sitefetch.Cache_Revalidate;
      elsif Text = "refresh" or else Text = "force-refresh" then
         Options.Limits.Cache.Mode := Sitefetch.Cache_Refresh;
      elsif Text = "offline" or else Text = "offline-only" then
         Options.Limits.Cache.Mode := Sitefetch.Cache_Offline;
      else
         Set_Error (Options, "error.unknown_option", "option", "--cache");
         Failed := True;
      end if;
   end Set_Cache_Mode;

   procedure Set_Cache_Hash
     (Options : in out Parsed_Options;
      Text    : String;
      Failed  : out Boolean)
     with SPARK_Mode => On
   is
   begin
      Failed := False;
      if Text = "fnv1a-64" or else Text = "fnv" or else Text = "default" then
         Options.Limits.Cache.Hash_Algorithm := Sitefetch.Cache_Hash_FNV1a_64;
      elsif Text = "sha256" or else Text = "sha-256" then
         Options.Limits.Cache.Hash_Algorithm := Sitefetch.Cache_Hash_SHA256;
      elsif Text = "none" or else Text = "off" or else Text = "size-only" then
         Options.Limits.Cache.Hash_Algorithm := Sitefetch.Cache_Hash_None;
      else
         Set_Error (Options, "error.unknown_option", "option", "--cache-hash");
         Failed := True;
      end if;
   end Set_Cache_Hash;

   procedure Parse_One
     (Arguments        : Argument_Array;
      Argument_Index   : in out Positive;
      Options          : in out Parsed_Options;
      Positional_Count : in out Natural;
      Failed           : out Boolean)
     with SPARK_Mode => On
   is
      Argument : constant String := To_String (Arguments (Argument_Index));
   begin
      Failed := False;

      if Argument = "--help" or else Argument = "-h" then
         Options.Status := Parse_Show_Help;
      elsif Argument = "--version" then
         Options.Status := Parse_Show_Version;
      elsif Argument = "--quiet" or else Argument = "-q" then
         Options.Quiet := True;
      elsif Argument = "--verbose" or else Argument = "-v" then
         Options.Verbose := True;
         Options.Limits.Diagnostics.Mode := Sitefetch.Diagnostics_Verbose;
      elsif Argument = "--jsonl" then
         Options.JSONL_Output := True;
      elsif Argument = "--json-summary" then
         Options.JSON_Summary := True;
      elsif Argument = "--skip-dangerous" then
         Options.Limits.Safety.Mode := Sitefetch.Safety_Skip_Dangerous;
      elsif Argument = "--durable-writes" then
         Options.Limits.Safety.Write_Durability := Sitefetch.Write_Durability_Sync_Data_And_Directory;
      elsif Argument = "--safe" or else Argument = "--assets-only-safe" then
         Options.Limits.Safety.Mode := Sitefetch.Safety_Assets_Only_Safe;
      elsif Argument = "--include-parent-domains" then
         Options.Limits.Crawl.Domain := Sitefetch.Domain_Include_Parents;
      elsif Argument = "--robots" or else Argument = "--respect-robots" then
         Options.Limits.Crawl.Robots := Sitefetch.Robots_Respect;
      elsif Argument = "--ignore-robots" then
         Options.Limits.Crawl.Robots := Sitefetch.Robots_Ignore;
      elsif Argument = "--robots-fail-closed" then
         Options.Limits.Crawl.Robots_Failure := Sitefetch.Robots_Fail_Closed;
      elsif Argument = "--robots-fail-open" then
         Options.Limits.Crawl.Robots_Failure := Sitefetch.Robots_Fail_Open;
      elsif Argument = "--incremental" or else Argument = "--revalidate-cache" then
         Options.Limits.Cache.Mode := Sitefetch.Cache_Revalidate;
      elsif Argument = "--refresh-cache" then
         Options.Limits.Cache.Mode := Sitefetch.Cache_Refresh;
      elsif Argument = "--offline-cache" then
         Options.Limits.Cache.Mode := Sitefetch.Cache_Offline;
      elsif Argument = "--cache" then
         if Argument_Index = Arguments'Last then
            Set_Error (Options, "error.unknown_option", "option", Argument);
            Failed := True;
         else
            Argument_Index := Argument_Index + 1;
            Set_Cache_Mode (Options, To_String (Arguments (Argument_Index)), Failed);
         end if;
      elsif Argument = "--cache-vary-accept-language" then
         Options.Limits.Cache.Vary_Allow.Accept_Language := True;
      elsif Argument = "--cache-vary-accept-encoding" then
         Options.Limits.Cache.Vary_Allow.Accept_Encoding := True;
      elsif Argument = "--cache-require-version" then
         Options.Limits.Cache.Require_Metadata_Version := True;
      elsif Argument = "--cache-no-verify-local" then
         Options.Limits.Cache.Verify_Local_Content := False;
      elsif Argument = "--cache-all" then
         Options.Limits.Cache.Resource_Strategy := Sitefetch.Cache_All_Resources;
      elsif Argument = "--cache-documents-only" then
         Options.Limits.Cache.Resource_Strategy := Sitefetch.Cache_Documents_Only;
      elsif Argument = "--cache-downloads-only" then
         Options.Limits.Cache.Resource_Strategy := Sitefetch.Cache_Downloads_Only;
      elsif Argument = "--no-cache" then
         Options.Limits.Cache.Mode := Sitefetch.Cache_Ignore;
      elsif Argument = "--no-head" then
         Options.Limits.HTTP.Head := Sitefetch.Head_Disabled;
      elsif Argument = "--head" then
         if Argument_Index = Arguments'Last then
            Set_Error (Options, "error.unknown_option", "option", Argument);
            Failed := True;
         else
            Argument_Index := Argument_Index + 1;
            Set_Head_Policy (Options, To_String (Arguments (Argument_Index)), Failed);
         end if;
      elsif Argument = "--cache-hash" then
         if Argument_Index = Arguments'Last then
            Set_Error (Options, "error.unknown_option", "option", Argument);
            Failed := True;
         else
            Argument_Index := Argument_Index + 1;
            Set_Cache_Hash (Options, To_String (Arguments (Argument_Index)), Failed);
         end if;
      elsif Argument = "--max-pages" or else Argument = "--max-depth"
        or else Argument = "--max-bytes" or else Argument = "--max-failures"
        or else Argument = "--retries" or else Argument = "--retry-delay-ms"
        or else Argument = "--retry-jitter-ms"
        or else Argument = "--request-delay-ms" or else Argument = "--cache-max-stale-ms"
        or else Argument = "--max-per-host"
        or else Argument = "--workers" then
         if Argument_Index = Arguments'Last then
            Set_Error (Options, "error.unknown_option", "option", Argument);
            Failed := True;
         else
            Argument_Index := Argument_Index + 1;
            Set_Limit (Options, Argument, To_String (Arguments (Argument_Index)), Failed);
         end if;
      elsif Starts_With (Argument, "--max-pages=") then
         Set_Limit (Options, "--max-pages", Argument (Argument'First + 12 .. Argument'Last), Failed);
      elsif Starts_With (Argument, "--max-depth=") then
         Set_Limit (Options, "--max-depth", Argument (Argument'First + 12 .. Argument'Last), Failed);
      elsif Starts_With (Argument, "--max-bytes=") then
         Set_Limit (Options, "--max-bytes", Argument (Argument'First + 12 .. Argument'Last), Failed);
      elsif Starts_With (Argument, "--max-failures=") then
         Set_Limit (Options, "--max-failures", Argument (Argument'First + 15 .. Argument'Last), Failed);
      elsif Starts_With (Argument, "--retries=") then
         Set_Limit (Options, "--retries", Argument (Argument'First + 10 .. Argument'Last), Failed);
      elsif Starts_With (Argument, "--retry-delay-ms=") then
         Set_Limit (Options, "--retry-delay-ms", Argument (Argument'First + 17 .. Argument'Last), Failed);
      elsif Starts_With (Argument, "--retry-jitter-ms=") then
         Set_Limit (Options, "--retry-jitter-ms", Argument (Argument'First + 18 .. Argument'Last), Failed);
      elsif Starts_With (Argument, "--request-delay-ms=") then
         Set_Limit (Options, "--request-delay-ms", Argument (Argument'First + 19 .. Argument'Last), Failed);
      elsif Starts_With (Argument, "--cache-max-stale-ms=") then
         Set_Limit (Options, "--cache-max-stale-ms", Argument (Argument'First + 21 .. Argument'Last), Failed);
      elsif Starts_With (Argument, "--max-per-host=") then
         Set_Limit (Options, "--max-per-host", Argument (Argument'First + 15 .. Argument'Last), Failed);
      elsif Starts_With (Argument, "--workers=") then
         if Argument'Length = 10 then
            Set_Limit (Options, "--workers", "", Failed);
         else
            Set_Limit (Options, "--workers", Argument (Argument'First + 10 .. Argument'Last), Failed);
         end if;
      elsif Starts_With (Argument, "--head=") then
         if Argument'Length = 7 then
            Set_Head_Policy (Options, "", Failed);
         else
            Set_Head_Policy (Options, Argument (Argument'First + 7 .. Argument'Last), Failed);
         end if;
      elsif Starts_With (Argument, "--cache=") then
         if Argument'Length = 8 then
            Set_Cache_Mode (Options, "", Failed);
         else
            Set_Cache_Mode (Options, Argument (Argument'First + 8 .. Argument'Last), Failed);
         end if;
      elsif Starts_With (Argument, "--cache-hash=") then
         if Argument'Length = 13 then
            Set_Cache_Hash (Options, "", Failed);
         else
            Set_Cache_Hash (Options, Argument (Argument'First + 13 .. Argument'Last), Failed);
         end if;
      elsif Argument = "--user-agent" then
         if Argument_Index = Arguments'Last then
            Set_Error (Options, "error.unknown_option", "option", Argument);
            Failed := True;
         elsif To_String (Arguments (Argument_Index + 1)) = "" then
            Set_Error (Options, "error.unknown_option", "option", Argument);
            Failed := True;
         else
            Argument_Index := Argument_Index + 1;
            Options.Limits.HTTP.User_Agent := Arguments (Argument_Index);
         end if;
      elsif Starts_With (Argument, "--user-agent=") then
         if Argument'Length = 13 then
            Set_Error (Options, "error.unknown_option", "option", "--user-agent");
            Failed := True;
         else
            Options.Limits.HTTP.User_Agent := To_Unbounded_String
              (Argument (Argument'First + 13 .. Argument'Last));
         end if;
      elsif Argument = "--accept-language" then
         if Argument_Index = Arguments'Last then
            Set_Error (Options, "error.unknown_option", "option", Argument);
            Failed := True;
         elsif To_String (Arguments (Argument_Index + 1)) = "" then
            Set_Error (Options, "error.unknown_option", "option", Argument);
            Failed := True;
         else
            Argument_Index := Argument_Index + 1;
            Options.Limits.HTTP.Accept_Language := Arguments (Argument_Index);
         end if;
      elsif Starts_With (Argument, "--accept-language=") then
         if Argument'Length = 18 then
            Set_Error (Options, "error.unknown_option", "option", "--accept-language");
            Failed := True;
         else
            Options.Limits.HTTP.Accept_Language := To_Unbounded_String
              (Argument (Argument'First + 18 .. Argument'Last));
         end if;
      elsif Argument = "--accept-encoding" then
         if Argument_Index = Arguments'Last then
            Set_Error (Options, "error.unknown_option", "option", Argument);
            Failed := True;
         elsif To_String (Arguments (Argument_Index + 1)) = "" then
            Set_Error (Options, "error.unknown_option", "option", Argument);
            Failed := True;
         else
            Argument_Index := Argument_Index + 1;
            Options.Limits.HTTP.Accept_Encoding := Arguments (Argument_Index);
         end if;
      elsif Starts_With (Argument, "--accept-encoding=") then
         if Argument'Length = 18 then
            Set_Error (Options, "error.unknown_option", "option", "--accept-encoding");
            Failed := True;
         else
            Options.Limits.HTTP.Accept_Encoding := To_Unbounded_String
              (Argument (Argument'First + 18 .. Argument'Last));
         end if;
      elsif Argument = "--locale" then
         if Argument_Index = Arguments'Last then
            Set_Error (Options, "error.locale_missing");
            Failed := True;
         elsif To_String (Arguments (Argument_Index + 1)) = "" then
            Set_Error (Options, "error.locale_empty");
            Failed := True;
         else
            Argument_Index := Argument_Index + 1;
            Options.Locale_Provided := True;
            Options.Locale := Arguments (Argument_Index);
         end if;
      elsif Starts_With (Argument, "--locale=") then
         if Argument'Length = 9 then
            Set_Error (Options, "error.locale_empty");
            Failed := True;
         else
            Options.Locale_Provided := True;
            Options.Locale := To_Unbounded_String
              (Argument (Argument'First + 9 .. Argument'Last));
         end if;
      elsif Starts_With_Dash (Argument) then
         Set_Error (Options, "error.unknown_option", "option", Argument);
         Failed := True;
      else
         Positional_Count := Positional_Count + 1;

         if Positional_Count = 1 then
            Options.Source_URL := To_Unbounded_String (Argument);
         elsif Positional_Count = 2 then
            Options.Target_Directory := To_Unbounded_String (Argument);
         else
            Set_Error (Options, "error.too_many_arguments");
            Failed := True;
         end if;
      end if;
   end Parse_One;

   function Parse (Arguments : Argument_Array) return Parsed_Options
     with SPARK_Mode => On
   is
      Options          : Parsed_Options;
      Argument_Index   : Positive := Arguments'First;
      Positional_Count : Natural := 0;
      Failed           : Boolean;
   begin
      Options.Status := Parse_Ok;

      while Argument_Index <= Arguments'Last loop
         Parse_One (Arguments, Argument_Index, Options, Positional_Count, Failed);

         if Failed then
            return Options;
         end if;

         Argument_Index := Argument_Index + 1;
      end loop;

      if Options.Status = Parse_Show_Help or else Options.Status = Parse_Show_Version then
         return Options;
      elsif Positional_Count = 0 then
         Set_Error (Options, "error.missing_url");
      end if;

      return Options;
   end Parse;

   function Parse_Command_Line return Parsed_Options is
      Count : constant Natural := Ada.Command_Line.Argument_Count;
   begin
      if Count = 0 then
         declare
            Empty : Argument_Array (1 .. 1) := [To_Unbounded_String ("")];
            Result : Parsed_Options := Parse (Empty);
         begin
            Set_Error (Result, "error.missing_url");
            return Result;
         end;
      else
         declare
            Arguments : Argument_Array (1 .. Count);
         begin
            for Index_Value in Arguments'Range loop
               Arguments (Index_Value) := To_Unbounded_String (Ada.Command_Line.Argument (Index_Value));
            end loop;

            return Parse (Arguments);
         end;
      end if;
   end Parse_Command_Line;
end Sitefetch.CLI;
