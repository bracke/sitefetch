with Ada.Calendar;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Sitefetch.App_Format;
with Sitefetch.Messages;
with Sitefetch.Progress;
with Sitefetch.Crawler;
with Terminal_Styles;

package body Sitefetch.App is
   use Ada.Strings.Unbounded;
   use Sitefetch.App_Format;
   use type Ada.Calendar.Time;
   use type Ada.Directories.File_Kind;
   use type Sitefetch.CLI.Parse_Status;
   use type Website_Fetcher;

   Version : constant String := "0.1.0";

   JSON_Output : Line_Sink := null;

   procedure Put_Line (Sink : Line_Sink; Text : String);

   function Reason_Start (Text : String) return Natural is
   begin
      if Text'Length < 3 or else Text (Text'Last) /= ')' then
         return 0;
      end if;

      for Index_Value in reverse Text'First .. Text'Last - 2 loop
         if Text (Index_Value) = ' ' and then Text (Index_Value + 1) = '(' then
            return Index_Value;
         end if;
      end loop;

      return 0;
   end Reason_Start;

   function Retry_Attempt_From_Reason (Reason : String) return Natural is
      Prefix : constant String := "attempt ";
      First  : Natural := Reason'First + Prefix'Length;
      Value  : Natural := 0;
   begin
      if Reason'Length <= Prefix'Length
        or else Reason (Reason'First .. Reason'First + Prefix'Length - 1) /= Prefix
      then
         return 0;
      end if;

      while First <= Reason'Last and then Reason (First) in '0' .. '9' loop
         if Value > (Natural'Last - Character'Pos (Reason (First)) + Character'Pos ('0')) / 10 then
            return 0;
         end if;
         Value := Value * 10 + Character'Pos (Reason (First)) - Character'Pos ('0');
         First := First + 1;
      end loop;

      return Value;
   end Retry_Attempt_From_Reason;

   function Status_Code_From_Reason (Reason : String) return Natural is
      Marker : constant String := "HTTP_";
      Start  : constant Natural := Ada.Strings.Fixed.Index (Reason, Marker);
      Cursor : Natural;
      Value  : Natural := 0;
   begin
      if Start = 0 then
         return 0;
      end if;

      Cursor := Start + Marker'Length;
      while Cursor <= Reason'Last and then Reason (Cursor) in '0' .. '9' loop
         if Value > (Natural'Last - Character'Pos (Reason (Cursor)) + Character'Pos ('0')) / 10 then
            return 0;
         end if;
         Value := Value * 10 + Character'Pos (Reason (Cursor)) - Character'Pos ('0');
         Cursor := Cursor + 1;
      end loop;

      return Value;
   end Status_Code_From_Reason;

   type JSON_Summary_Counters is record
      Retries             : Natural := 0;
      Cache_Hits          : Natural := 0;
      Cache_Revalidations : Natural := 0;
      Cache_Rejections    : Natural := 0;
      Robots_Allowed      : Natural := 0;
      Robots_Disallowed   : Natural := 0;
      Robots_Loaded       : Natural := 0;
      Robots_Failed       : Natural := 0;
      Redirects           : Natural := 0;
      Redirect_Hops       : Natural := 0;
   end record;

   package Cache_Rejection_Reason_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Natural);

   JSON_Summary_State : JSON_Summary_Counters := (others => <>);
   Cache_Rejection_Reasons : Cache_Rejection_Reason_Maps.Map;

   procedure Reset_JSON_Summary_State is
   begin
      JSON_Summary_State := (others => <>);
      Cache_Rejection_Reasons.Clear;
   end Reset_JSON_Summary_State;

   procedure Record_Cache_Rejection_Reason (Reason : String) is
   begin
      if Reason = "" then
         return;
      elsif Cache_Rejection_Reasons.Contains (Reason) then
         Cache_Rejection_Reasons.Replace
           (Reason, Cache_Rejection_Reasons.Element (Reason) + 1);
      else
         Cache_Rejection_Reasons.Insert (Reason, 1);
      end if;
   end Record_Cache_Rejection_Reason;

   function JSON_Cache_Rejection_Reasons return String is
      Result : Unbounded_String := To_Unbounded_String ("{");
      First  : Boolean := True;
   begin
      for Position in Cache_Rejection_Reasons.Iterate loop
         if First then
            First := False;
         else
            Append (Result, ",");
         end if;

         Append
           (Result,
            JSON_String (Cache_Rejection_Reason_Maps.Key (Position))
            & ":"
            & Natural_Image (Cache_Rejection_Reason_Maps.Element (Position)));
      end loop;
      Append (Result, "}");
      return To_String (Result);
   end JSON_Cache_Rejection_Reasons;

   procedure Record_JSON_Summary_Event (Progress : Sitefetch.Progress_Record) is
   begin
      case Progress.Event is
         when Sitefetch.Progress_Retry =>
            JSON_Summary_State.Retries := JSON_Summary_State.Retries + 1;
         when Sitefetch.Progress_Cache_Reused =>
            JSON_Summary_State.Cache_Hits := JSON_Summary_State.Cache_Hits + 1;
         when Sitefetch.Progress_Cache_Revalidate =>
            JSON_Summary_State.Cache_Revalidations := JSON_Summary_State.Cache_Revalidations + 1;
         when Sitefetch.Progress_Cache_Rejected =>
            JSON_Summary_State.Cache_Rejections := JSON_Summary_State.Cache_Rejections + 1;
            Record_Cache_Rejection_Reason (To_String (Progress.Reason));
         when Sitefetch.Progress_Robots_Allowed =>
            JSON_Summary_State.Robots_Allowed := JSON_Summary_State.Robots_Allowed + 1;
         when Sitefetch.Progress_Robots_Disallowed =>
            JSON_Summary_State.Robots_Disallowed := JSON_Summary_State.Robots_Disallowed + 1;
         when Sitefetch.Progress_Robots_Loaded =>
            JSON_Summary_State.Robots_Loaded := JSON_Summary_State.Robots_Loaded + 1;
         when Sitefetch.Progress_Robots_Failed =>
            JSON_Summary_State.Robots_Failed := JSON_Summary_State.Robots_Failed + 1;
         when Sitefetch.Progress_Redirected =>
            JSON_Summary_State.Redirects := JSON_Summary_State.Redirects + 1;
            if Progress.Redirect_Hops > Natural'Last - JSON_Summary_State.Redirect_Hops then
               JSON_Summary_State.Redirect_Hops := Natural'Last;
            else
               JSON_Summary_State.Redirect_Hops :=
                 JSON_Summary_State.Redirect_Hops + Progress.Redirect_Hops;
            end if;
         when others =>
            null;
      end case;
   end Record_JSON_Summary_Event;

   procedure Record_Structured_Progress (Progress : Sitefetch.Progress_Record) is
   begin
      Record_JSON_Summary_Event (Progress);
   end Record_Structured_Progress;

   procedure JSON_Structured_Progress (Progress : Sitefetch.Progress_Record) is
   begin
      Record_JSON_Summary_Event (Progress);
      Put_Line
        (JSON_Output,
         "{""type"":""progress"",""event"":"
         & JSON_String (Progress_Event_Name (Progress.Event))
         & ",""url"":" & JSON_String (To_String (Progress.URL))
         & ",""reason"":" & JSON_String (To_String (Progress.Reason))
         & ",""local_path"":" & JSON_String (To_String (Progress.Local_Path))
         & ",""bytes_written"":" & Natural_Image (Progress.Bytes_Written)
         & ",""depth"":" & Natural_Image (Progress.Depth)
         & ",""retry_attempt"":" & Natural_Image (Progress.Retry_Attempt)
         & ",""status_code"":" & Natural_Image (Progress.Status_Code)
         & ",""cache_decision"":" & JSON_String (To_String (Progress.Cache_Decision))
         & ",""robots_source"":" & JSON_String (To_String (Progress.Robots_Source))
         & ",""final_url"":" & JSON_String (To_String (Progress.Final_URL))
         & ",""source_id"":" & JSON_String (To_String (Progress.Source_ID))
         & ",""redirect_hops"":" & Natural_Image (Progress.Redirect_Hops)
         & ",""redirect_chain"":" & JSON_String (To_String (Progress.Redirect_Chain))
         & ",""redirect_status_codes"":"
         & JSON_String (To_String (Progress.Redirect_Status_Codes))
         & ",""redirect_target_urls"":"
         & JSON_String (To_String (Progress.Redirect_Target_URLs))
         & ",""redirect_locations"":"
         & JSON_String (To_String (Progress.Redirect_Locations))
         & "}");
   end JSON_Structured_Progress;

   procedure JSON_Progress
     (Event : Sitefetch.Progress_Event;
      URL   : String)
   is
      Split       : constant Natural := Reason_Start (URL);
      URL_Text    : constant String :=
        (if Split > URL'First then URL (URL'First .. Split - 1) else URL);
      Reason_Text : constant String :=
        (if Split > URL'First then URL (Split + 2 .. URL'Last - 1) else "");
   begin
      JSON_Structured_Progress
        (Sitefetch.Progress_Record'
           (Event          => Event,
            URL            => To_Unbounded_String (URL_Text),
            Reason         => To_Unbounded_String (Reason_Text),
            Local_Path     => Null_Unbounded_String,
            Bytes_Written  => 0,
            Depth          => 0,
            Status_Code    => Status_Code_From_Reason (Reason_Text),
            Retry_Attempt  => Retry_Attempt_From_Reason (Reason_Text),
            Cache_Decision => To_Unbounded_String (Cache_Decision_For (Event)),
            Robots_Source  => To_Unbounded_String (Robots_Source_For (Event)),
            Final_URL      => Null_Unbounded_String,
            Source_ID      => Null_Unbounded_String,
            Redirect_Hops         => 0,
            Redirect_Chain        => Null_Unbounded_String,
            Redirect_Status_Codes => Null_Unbounded_String,
            Redirect_Target_URLs  => Null_Unbounded_String,
            Redirect_Locations    => Null_Unbounded_String));
   end JSON_Progress;

   procedure Put_Line (Sink : Line_Sink; Text : String) is
   begin
      if Sink /= null then
         Sink (Text);
      end if;
   end Put_Line;

   procedure Print_Usage (Output : Line_Sink) is
   begin
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("usage.line1"), Terminal_Styles.Role_Header));
      Put_Line
        (Output,
         Terminal_Styles.Decorate
           (Sitefetch.Messages.Text ("usage.line2"), Terminal_Styles.Role_Info));
      Put_Line (Output, "");
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("usage.description"), Terminal_Styles.Role_Info));
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("usage.scheme"), Terminal_Styles.Role_Muted));
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("usage.quiet"), Terminal_Styles.Role_Muted));
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("usage.verbose"), Terminal_Styles.Role_Muted));
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("usage.locale"), Terminal_Styles.Role_Muted));
   end Print_Usage;

   procedure Print_Error (Error_Output : Line_Sink; Message : String) is
   begin
      Put_Line
        (Error_Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("error.prefix", "message", Message),
            Terminal_Styles.Role_Error));
   end Print_Error;

   procedure Print_Parse_Error
     (Options      : Sitefetch.CLI.Parsed_Options;
      Error_Output : Line_Sink)
   is
      use Ada.Strings.Unbounded;
   begin
      if Length (Options.Error_Arg_Key) > 0 then
         Print_Error
           (Error_Output,
            Sitefetch.Messages.Text
              (To_String (Options.Error_Key),
               To_String (Options.Error_Arg_Key),
               To_String (Options.Error_Arg_Value)));
      else
         Print_Error (Error_Output, Sitefetch.Messages.Text (To_String (Options.Error_Key)));
      end if;
   end Print_Parse_Error;

   function Target_Is_Usable (Target_Directory : String; Error_Output : Line_Sink) return Boolean is
   begin
      if Target_Directory = "" then
         Print_Error (Error_Output, Sitefetch.Messages.Text ("error.target_empty"));
         return False;
      elsif Ada.Directories.Exists (Target_Directory)
        and then Ada.Directories.Kind (Target_Directory) /= Ada.Directories.Directory
      then
         Print_Error
           (Error_Output,
            Sitefetch.Messages.Text ("error.target_not_directory", "target", Target_Directory));
         return False;
      else
         return True;
      end if;
   exception
      when others =>
         Print_Error
           (Error_Output,
            Sitefetch.Messages.Text ("error.target_inspect", "target", Target_Directory));
         return False;
   end Target_Is_Usable;

   function Duration_Image (Value : Duration) return String is
      Non_Negative_Value : constant Duration := (if Value < 0.0 then 0.0 else Value);
      Text               : constant String :=
        Ada.Strings.Fixed.Trim (Duration'Image (Non_Negative_Value), Ada.Strings.Left);
   begin
      return Text & "s";
   end Duration_Image;

   procedure Print_Summary
     (Statistics   : Sitefetch.Fetch_Statistics;
      Success      : Boolean;
      Elapsed      : Duration;
      Output       : Line_Sink;
      Error_Output : Line_Sink)
   is
      use Ada.Strings.Unbounded;
   begin
      if Success then
         Put_Line
           (Output,
            Terminal_Styles.Line
              (Sitefetch.Messages.Text ("status.completed"), Terminal_Styles.Role_Success));
      else
         Put_Line
           (Error_Output,
            Terminal_Styles.Line
              ((if Length (Statistics.Failed_Reason) > 0 then
                   Sitefetch.Messages.Text
                     ("status.failed_reason", "reason", To_String (Statistics.Failed_Reason))
                else
                   Sitefetch.Messages.Text ("status.failed")),
               Terminal_Styles.Role_Error));
      end if;

      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("summary.attempted", "count", Natural_Image (Statistics.Attempted)),
            Terminal_Styles.Role_Info));
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("summary.written", "count", Natural_Image (Statistics.Written)),
            Terminal_Styles.Role_Success));
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("summary.external", "count", Natural_Image (Statistics.Skipped_External)),
            Terminal_Styles.Role_Warning));
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text
              ("summary.ignored", "count", Natural_Image (Statistics.Skipped_Unsupported)),
            Terminal_Styles.Role_Muted));
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("summary.failed", "count", Natural_Image (Statistics.Failed)),
            Terminal_Styles.Role_Error));
      Put_Line
        (Output,
         Terminal_Styles.Line
           (Sitefetch.Messages.Text ("summary.elapsed", "duration", Duration_Image (Elapsed)),
            Terminal_Styles.Role_Info));

      if not Statistics.Failed_Downloads.Is_Empty then
         for Failure of Statistics.Failed_Downloads loop
            Put_Line
              (Error_Output,
               Terminal_Styles.Line
                 (Sitefetch.Messages.Text ("summary.failed_url", "url", To_String (Failure.URL)),
                  Terminal_Styles.Role_Error));

            if Length (Failure.Reason) > 0 then
               Put_Line
                 (Error_Output,
                  Terminal_Styles.Line
                    (Sitefetch.Messages.Text
                       ("summary.failed_reason", "reason", To_String (Failure.Reason)),
                     Terminal_Styles.Role_Error));
            end if;
         end loop;
      elsif Length (Statistics.Failed_URL) > 0 then
         Put_Line
           (Error_Output,
            Terminal_Styles.Line
              (Sitefetch.Messages.Text ("summary.failed_url", "url", To_String (Statistics.Failed_URL)),
               Terminal_Styles.Role_Error));

         if Length (Statistics.Failed_Reason) > 0 then
            Put_Line
              (Error_Output,
               Terminal_Styles.Line
                 (Sitefetch.Messages.Text
                    ("summary.failed_reason", "reason", To_String (Statistics.Failed_Reason)),
                  Terminal_Styles.Role_Error));
         end if;
      end if;
   end Print_Summary;

   function JSON_Failure_Downloads (Statistics : Sitefetch.Fetch_Statistics) return String is
      use Ada.Strings.Unbounded;
      Result : Unbounded_String := To_Unbounded_String ("[");
      First  : Boolean := True;
   begin
      for Failure of Statistics.Failed_Downloads loop
         if not First then
            Append (Result, ",");
         end if;
         First := False;
         Append
           (Result,
            "{""url"":" & JSON_String (To_String (Failure.URL))
            & ",""reason"":" & JSON_String (To_String (Failure.Reason)) & "}");
      end loop;
      Append (Result, "]");
      return To_String (Result);
   end JSON_Failure_Downloads;

   procedure Print_JSON_Summary
     (Statistics : Sitefetch.Fetch_Statistics;
      Success    : Boolean;
      Elapsed    : Duration;
      Output     : Line_Sink)
   is
      use Ada.Strings.Unbounded;
   begin
      Put_Line
        (Output,
         "{""type"":""summary"",""success"":" & JSON_Boolean (Success)
         & ",""attempted"":" & Natural_Image (Statistics.Attempted)
         & ",""written"":" & Natural_Image (Statistics.Written)
         & ",""skipped_external"":" & Natural_Image (Statistics.Skipped_External)
         & ",""skipped_unsupported"":" & Natural_Image (Statistics.Skipped_Unsupported)
         & ",""skipped_limit"":" & Natural_Image (Statistics.Skipped_Limit)
         & ",""bytes_written"":" & Natural_Image (Statistics.Bytes_Written)
         & ",""failed"":" & Natural_Image (Statistics.Failed)
         & ",""retries"":" & Natural_Image (JSON_Summary_State.Retries)
         & ",""cache_hits"":" & Natural_Image (JSON_Summary_State.Cache_Hits)
         & ",""cache_revalidations"":" & Natural_Image (JSON_Summary_State.Cache_Revalidations)
         & ",""cache_rejections"":" & Natural_Image (JSON_Summary_State.Cache_Rejections)
         & ",""cache_rejection_reasons"":" & JSON_Cache_Rejection_Reasons
         & ",""robots_allowed"":" & Natural_Image (JSON_Summary_State.Robots_Allowed)
         & ",""robots_disallowed"":" & Natural_Image (JSON_Summary_State.Robots_Disallowed)
         & ",""robots_loaded"":" & Natural_Image (JSON_Summary_State.Robots_Loaded)
         & ",""robots_failed"":" & Natural_Image (JSON_Summary_State.Robots_Failed)
         & ",""redirects"":" & Natural_Image (JSON_Summary_State.Redirects)
         & ",""redirect_hops"":" & Natural_Image (JSON_Summary_State.Redirect_Hops)
         & ",""elapsed_seconds"":"
         & Ada.Strings.Fixed.Trim (Duration'Image ((if Elapsed < 0.0 then 0.0 else Elapsed)), Ada.Strings.Left)
         & ",""failed_url"":" & JSON_String (To_String (Statistics.Failed_URL))
         & ",""failed_reason"":" & JSON_String (To_String (Statistics.Failed_Reason))
         & ",""failed_download_count"":" & Natural_Image (Natural (Statistics.Failed_Downloads.Length))
         & ",""failed_downloads"":" & JSON_Failure_Downloads (Statistics)
         & "}");
   end Print_JSON_Summary;

   function Production_Fetch
     (URL              : String;
      Target_Directory : String;
      Statistics       : out Sitefetch.Fetch_Statistics;
      Progress         : Sitefetch.Progress_Callback;
      Options          : Sitefetch.Fetch_Options) return Boolean
   is
   begin
      return Sitefetch.Crawler.Fetch_Website (URL, Target_Directory, Statistics, Progress, Options);
   end Production_Fetch;

   procedure Console_Output (Line : String) is
   begin
      Ada.Text_IO.Put_Line (Line);
   end Console_Output;

   procedure Console_Error (Line : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Line);
   end Console_Error;

   function Run
     (Options      : Sitefetch.CLI.Parsed_Options;
      Fetcher      : Website_Fetcher;
      Output       : Line_Sink;
      Error_Output : Line_Sink) return Exit_Status
   is
      use Ada.Strings.Unbounded;

      Source_URL       : Unbounded_String;
      Target_Directory : Unbounded_String;
      Statistics       : Sitefetch.Fetch_Statistics;
      Progress_Hook    : Sitefetch.Progress_Callback := Sitefetch.Progress'Access;
      Structured_Output : constant Boolean := Options.JSONL_Output or else Options.JSON_Summary;
      Success          : Boolean;
      Start_Time       : Ada.Calendar.Time;
      Elapsed_Time     : Duration := 0.0;
   begin
      if Options.Locale_Provided then
         Sitefetch.Messages.Set_Locale (To_String (Options.Locale));
      else
         Sitefetch.Messages.Detect_System_Locale;
      end if;

      if Options.Status = Sitefetch.CLI.Parse_Error then
         Print_Parse_Error (Options, Error_Output);
         Print_Usage (Output);
         return Exit_Failure;
      elsif Options.Status = Sitefetch.CLI.Parse_Show_Help then
         Print_Usage (Output);
         return Exit_Success;
      elsif Options.Status = Sitefetch.CLI.Parse_Show_Version then
         Put_Line
           (Output,
            Terminal_Styles.Line
              (Sitefetch.Messages.Text ("version", "version", Version), Terminal_Styles.Role_Header));
         return Exit_Success;
      end if;

      Source_URL := Options.Source_URL;
      Target_Directory := Options.Target_Directory;

      if not Target_Is_Usable (To_String (Target_Directory), Error_Output) then
         return Exit_Failure;
      end if;

      Reset_JSON_Summary_State;
      if Options.JSONL_Output then
         JSON_Output := Output;
         Progress_Hook := JSON_Progress'Access;
      elsif Options.Quiet or else Structured_Output then
         Progress_Hook := null;
      end if;

      if not Options.Quiet and then not Structured_Output then
         Put_Line
           (Output,
            Terminal_Styles.Line
              (Sitefetch.Messages.Text
                 ("start.fetching", "url", Sitefetch.Ensure_HTTP_Scheme (To_String (Source_URL))),
               Terminal_Styles.Role_Info));
         Put_Line
           (Output,
            Terminal_Styles.Line
              (Sitefetch.Messages.Text ("start.target", "target", To_String (Target_Directory)),
               Terminal_Styles.Role_Muted));
      end if;

      Start_Time := Ada.Calendar.Clock;
      begin
         if Structured_Output and then Fetcher = Production_Fetch'Access then
            if Options.JSONL_Output then
               Success := Sitefetch.Crawler.Fetch_Website_With_Structured_Progress
                 (To_String (Source_URL),
                  To_String (Target_Directory),
                  Statistics,
                  JSON_Structured_Progress'Access,
                  Options.Limits);
            else
               Success := Sitefetch.Crawler.Fetch_Website_With_Structured_Progress
                 (To_String (Source_URL),
                  To_String (Target_Directory),
                  Statistics,
                  Record_Structured_Progress'Access,
                  Options.Limits);
            end if;
         else
            Success := Fetcher
              (To_String (Source_URL),
               To_String (Target_Directory),
               Statistics,
               Progress_Hook,
               Options.Limits);
         end if;
      exception
         when others =>
            Print_Error (Error_Output, Sitefetch.Messages.Text ("error.fetch_exception"));
            Statistics.Failed := 1;
            Statistics.Failed_Reason := To_Unbounded_String (Sitefetch.Messages.Text ("error.fetch_exception"));
            Statistics.Failed_Downloads.Append
              (Sitefetch.Failed_Download'
                 (URL    => Source_URL,
                  Reason => Statistics.Failed_Reason));
            Success := False;
      end;
      Elapsed_Time := Ada.Calendar.Clock - Start_Time;

      if Options.JSONL_Output or else Options.JSON_Summary then
         Print_JSON_Summary (Statistics, Success, Elapsed_Time, Output);
      elsif not Options.Quiet then
         Print_Summary (Statistics, Success, Elapsed_Time, Output, Error_Output);
      end if;

      JSON_Output := null;

      if Success then
         return Exit_Success;
      else
         return Exit_Failure;
      end if;
   end Run;

   function Run
     (Options      : Sitefetch.CLI.Parsed_Options;
      Output       : Line_Sink;
      Error_Output : Line_Sink) return Exit_Status
   is
   begin
      return Run (Options, Production_Fetch'Access, Output, Error_Output);
   end Run;

   function Run (Options : Sitefetch.CLI.Parsed_Options) return Exit_Status is
   begin
      return Run (Options, Production_Fetch'Access, Console_Output'Access, Console_Error'Access);
   end Run;
end Sitefetch.App;
