with Ada.Calendar;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;
with GNAT.Sockets;

with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with AUnit.Test_Suites;

with Project_Tools.Files;


with Sitefetch.App;
with Sitefetch.CLI;
with Sitefetch.Crawler;
with Sitefetch.Messages;
with Sitefetch.Progress_Format;
with Terminal_Styles;
with Zlib;

package body Sitefetch.Tests is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use AUnit.Assertions;
   use type Zlib.Status_Code;

   type CLI_Parse_Test is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type App_Run_Test is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Message_Locale_Test is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Terminal_Format_Test is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Release_Manifest_Tool_Test is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Catalog_Completeness_Test is new AUnit.Simple_Test_Cases.Test_Case with null record;

   Structured_Progress_Count : Natural := 0;
   Last_Structured_Event     : Sitefetch.Progress_Event := Sitefetch.Progress_Fetching;
   Last_Structured_URL       : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Reason    : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Written_URL : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Written_Bytes : Natural := 0;
   Last_Structured_Written_Depth : Natural := 0;
   Last_Structured_Written_Status : Natural := 0;
   Last_Structured_Written_Local_Path : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Written_Final_URL : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Written_Source_ID : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Failed_Local_Path : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Failed_Final_URL : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Failed_Source_ID : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Failed_Status : Natural := 0;
   Last_Structured_Retry_URL : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Retry_Final_URL : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Retry_Source_ID : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Retry_Attempt : Natural := 0;
   Last_Structured_Retry_Status : Natural := 0;
   Last_Structured_Cache_URL : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Cache_Decision : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Cache_Local_Path : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Robots_URL : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Robots_Source : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Final_URL : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Source_ID : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Redirect_Hops : Natural := 0;
   Last_Structured_Redirect_Chain : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Redirect_Status_Codes : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Redirect_Target_URLs : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Redirect_Locations : Unbounded_String := Null_Unbounded_String;
   Last_Structured_Redirect_Status : Natural := 0;
   Output_Count              : Natural := 0;
   Error_Count               : Natural := 0;
   Last_Output_Line          : Unbounded_String := Null_Unbounded_String;
   Output_Text               : Unbounded_String := Null_Unbounded_String;
   Error_Text                : Unbounded_String := Null_Unbounded_String;
   Last_Error_Line           : Unbounded_String := Null_Unbounded_String;
   Last_App_URL              : Unbounded_String := Null_Unbounded_String;
   Last_App_Target           : Unbounded_String := Null_Unbounded_String;
   App_Progress_Was_Null     : Boolean := False;
   App_Fetch_Count           : Natural := 0;
   Last_App_Options          : Sitefetch.Fetch_Options := Sitefetch.Default_Fetch_Options;

   overriding function Name (Item : CLI_Parse_Test) return AUnit.Message_String;
   overriding function Name (Item : App_Run_Test) return AUnit.Message_String;
   overriding function Name (Item : Message_Locale_Test) return AUnit.Message_String;
   overriding function Name (Item : Terminal_Format_Test) return AUnit.Message_String;
   overriding function Name (Item : Release_Manifest_Tool_Test) return AUnit.Message_String;
   overriding function Name (Item : Catalog_Completeness_Test) return AUnit.Message_String;

   overriding procedure Run_Test (Item : in out CLI_Parse_Test);
   overriding procedure Run_Test (Item : in out App_Run_Test);
   overriding procedure Run_Test (Item : in out Message_Locale_Test);
   overriding procedure Run_Test (Item : in out Terminal_Format_Test);
   overriding procedure Run_Test (Item : in out Release_Manifest_Tool_Test);
   overriding procedure Run_Test (Item : in out Catalog_Completeness_Test);

   procedure Delete_Tree_If_Present (Path : String) is
   begin
      Project_Tools.Files.Delete_Tree (Path);
   end Delete_Tree_If_Present;

   function Read_File (Path : String) return String is
      File   : Ada.Text_IO.File_Type;
      Buffer : String (1 .. 1_024);
      Last   : Natural;
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Buffer, Last);
         if Last > 0 then
            Append (Result, Buffer (1 .. Last));
         end if;
      end loop;
      Ada.Text_IO.Close (File);
      return To_String (Result);
   end Read_File;

   function Containing_Test_Path (Path : String) return String is
   begin
      for Index_Value in reverse Path'Range loop
         if Path (Index_Value) = '/' then
            if Index_Value = Path'First then
               return ".";
            end if;

            return Path (Path'First .. Index_Value - 1);
         end if;
      end loop;

      return ".";
   end Containing_Test_Path;


   function Has_Generated_Atomic_Artifact
     (Directory : String; Base_Name : String) return Boolean
   is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Name   : Unbounded_String;
   begin
      if not Ada.Directories.Exists (Directory) then
         return False;
      end if;

      Ada.Directories.Start_Search
        (Search, Directory, Base_Name & ".sitefetch_*",
         (Ada.Directories.Ordinary_File => True,
          Ada.Directories.Directory => True,
          Ada.Directories.Special_File => True));
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Name := To_Unbounded_String (Ada.Directories.Simple_Name (Item));
         if Ada.Strings.Fixed.Index (To_String (Name), Base_Name & ".sitefetch_tmp.sitefetch_") = 1
           or else Ada.Strings.Fixed.Index (To_String (Name), Base_Name & ".sitefetch_old.sitefetch_") = 1
           or else Ada.Strings.Fixed.Index (To_String (Name), Base_Name & ".sitefetch_download.sitefetch_") = 1
         then
            Ada.Directories.End_Search (Search);
            return True;
         end if;
      end loop;
      Ada.Directories.End_Search (Search);
      return False;
   exception
      when others =>
         if Ada.Directories.More_Entries (Search) then
            Ada.Directories.End_Search (Search);
         end if;
         return False;
   end Has_Generated_Atomic_Artifact;

   procedure Write_Test_File (Path : String; Content : String) is
      File      : Ada.Text_IO.File_Type;
      Directory : constant String := Containing_Test_Path (Path);
   begin
      if Directory /= "." then
         Ada.Directories.Create_Path (Directory);
      end if;

      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (File, Content);
      Ada.Text_IO.Close (File);
   end Write_Test_File;

   procedure Write_Binary_Test_File (Path : String; Content : String) is
      use Ada.Streams;

      File      : Ada.Streams.Stream_IO.File_Type;
      Directory : constant String := Containing_Test_Path (Path);
      Data      : Stream_Element_Array (1 .. Stream_Element_Offset (Content'Length));
   begin
      if Directory /= "." then
         Ada.Directories.Create_Path (Directory);
      end if;

      for Index in Data'Range loop
         Data (Index) :=
           Stream_Element (Character'Pos (Content (Content'First + Natural (Index - Data'First))));
      end loop;

      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Write (File, Data);
      Ada.Streams.Stream_IO.Close (File);
   end Write_Binary_Test_File;

   type Progress_Event_Counts is array (Sitefetch.Progress_Event) of Natural;

   protected Parallel_Progress is
      procedure Reset;
      procedure Capture (Event : Sitefetch.Progress_Event);
      function Count (Event : Sitefetch.Progress_Event) return Natural;
   private
      Counts : Progress_Event_Counts := (others => 0);
   end Parallel_Progress;

   protected body Parallel_Progress is
      procedure Reset is
      begin
         Counts := (others => 0);
      end Reset;

      procedure Capture (Event : Sitefetch.Progress_Event) is
      begin
         Counts (Event) := Counts (Event) + 1;
      end Capture;

      function Count (Event : Sitefetch.Progress_Event) return Natural is
      begin
         return Counts (Event);
      end Count;
   end Parallel_Progress;

   procedure Record_Parallel_Progress (Event : Sitefetch.Progress_Event; URL : String) is
      pragma Unreferenced (URL);
   begin
      Parallel_Progress.Capture (Event);
   end Record_Parallel_Progress;

   procedure Record_Structured_Progress (Progress : Sitefetch.Progress_Record) is
   begin
      Structured_Progress_Count := Structured_Progress_Count + 1;
      Last_Structured_Event := Progress.Event;
      Last_Structured_URL := Progress.URL;
      Last_Structured_Reason := Progress.Reason;
      if Progress.Event = Sitefetch.Progress_Written then
         Last_Structured_Written_URL := Progress.URL;
         Last_Structured_Written_Bytes := Progress.Bytes_Written;
         Last_Structured_Written_Depth := Progress.Depth;
         Last_Structured_Written_Status := Progress.Status_Code;
         Last_Structured_Written_Local_Path := Progress.Local_Path;
         Last_Structured_Written_Final_URL := Progress.Final_URL;
         Last_Structured_Written_Source_ID := Progress.Source_ID;
      elsif Progress.Event = Sitefetch.Progress_Failed then
         Last_Structured_Failed_Local_Path := Progress.Local_Path;
         Last_Structured_Failed_Final_URL := Progress.Final_URL;
         Last_Structured_Failed_Source_ID := Progress.Source_ID;
         Last_Structured_Failed_Status := Progress.Status_Code;
      elsif Progress.Event = Sitefetch.Progress_Retry then
         Last_Structured_Retry_URL := Progress.URL;
         Last_Structured_Retry_Final_URL := Progress.Final_URL;
         Last_Structured_Retry_Source_ID := Progress.Source_ID;
         Last_Structured_Retry_Attempt := Progress.Retry_Attempt;
         Last_Structured_Retry_Status := Progress.Status_Code;
      elsif Progress.Event = Sitefetch.Progress_Cache_Reused
        or else Progress.Event = Sitefetch.Progress_Cache_Revalidate
      then
         if Progress.Event = Sitefetch.Progress_Cache_Revalidate
           or else Length (Last_Structured_Cache_Decision) = 0
         then
            Last_Structured_Cache_URL := Progress.URL;
            Last_Structured_Cache_Decision := Progress.Cache_Decision;
            Last_Structured_Cache_Local_Path := Progress.Local_Path;
         end if;
      elsif Progress.Event = Sitefetch.Progress_Robots_Loaded
        or else Progress.Event = Sitefetch.Progress_Robots_Failed
        or else Progress.Event = Sitefetch.Progress_Robots_Allowed
        or else Progress.Event = Sitefetch.Progress_Robots_Disallowed
      then
         Last_Structured_Robots_URL := Progress.URL;
         Last_Structured_Robots_Source := Progress.Robots_Source;
      elsif Progress.Event = Sitefetch.Progress_Redirected then
         Last_Structured_Final_URL := Progress.Final_URL;
         Last_Structured_Source_ID := Progress.Source_ID;
         Last_Structured_Redirect_Hops := Progress.Redirect_Hops;
         Last_Structured_Redirect_Chain := Progress.Redirect_Chain;
         Last_Structured_Redirect_Status_Codes := Progress.Redirect_Status_Codes;
         Last_Structured_Redirect_Target_URLs := Progress.Redirect_Target_URLs;
         Last_Structured_Redirect_Locations := Progress.Redirect_Locations;
         Last_Structured_Redirect_Status := Progress.Status_Code;
      end if;
   end Record_Structured_Progress;

   procedure Save_Environment
     (Name  : String;
      Found : out Boolean;
      Value : out Unbounded_String)
   is
   begin
      Found := Ada.Environment_Variables.Exists (Name);
      if Found then
         Value := To_Unbounded_String (Ada.Environment_Variables.Value (Name));
      else
         Value := Null_Unbounded_String;
      end if;
   end Save_Environment;

   procedure Restore_Environment
     (Name  : String;
      Found : Boolean;
      Value : Unbounded_String)
   is
   begin
      if Found then
         Ada.Environment_Variables.Set (Name, To_String (Value));
      else
         Ada.Environment_Variables.Clear (Name);
      end if;
   end Restore_Environment;

   procedure Reset_App_Fake is
   begin
      Output_Count := 0;
      Error_Count := 0;
      Last_Output_Line := Null_Unbounded_String;
      Output_Text := Null_Unbounded_String;
      Error_Text := Null_Unbounded_String;
      Last_Error_Line := Null_Unbounded_String;
      Last_App_URL := Null_Unbounded_String;
      Last_App_Target := Null_Unbounded_String;
      App_Progress_Was_Null := False;
      App_Fetch_Count := 0;
      Last_App_Options := Sitefetch.Default_Fetch_Options;
   end Reset_App_Fake;

   procedure Record_Output (Line : String) is
   begin
      Output_Count := Output_Count + 1;
      Last_Output_Line := To_Unbounded_String (Line);
      Append (Output_Text, Line);
      Append (Output_Text, Character'Val (10));
   end Record_Output;

   procedure Record_Error (Line : String) is
   begin
      Error_Count := Error_Count + 1;
      Last_Error_Line := To_Unbounded_String (Line);
      Append (Error_Text, Line);
      Append (Error_Text, Character'Val (10));
   end Record_Error;

   function Contains_Fragment (Text : String; Fragment : String) return Boolean is
   begin
      if Fragment'Length = 0 then
         return True;
      elsif Text'Length < Fragment'Length then
         return False;
      end if;

      for Index_Value in Text'First .. Text'Last - Fragment'Length + 1 loop
         if Text (Index_Value .. Index_Value + Fragment'Length - 1) = Fragment then
            return True;
         end if;
      end loop;

      return False;
   end Contains_Fragment;

   function Captured_Output_Has (Fragment : String) return Boolean is
      Text : constant String := To_String (Output_Text);
   begin
      return Contains_Fragment (Text, Fragment);
   end Captured_Output_Has;

   function Captured_Error_Has (Fragment : String) return Boolean is
      Text : constant String := To_String (Error_Text);
   begin
      return Contains_Fragment (Text, Fragment);
   end Captured_Error_Has;

   function App_Success_Fetcher
     (URL              : String;
      Target_Directory : String;
      Statistics       : out Sitefetch.Fetch_Statistics;
      Progress         : Sitefetch.Progress_Callback;
      Options          : Sitefetch.Fetch_Options) return Boolean
   is
   begin
      App_Fetch_Count := App_Fetch_Count + 1;
      Last_App_URL := To_Unbounded_String (URL);
      Last_App_Target := To_Unbounded_String (Target_Directory);
      App_Progress_Was_Null := Progress = null;
      Last_App_Options := Options;
      Statistics := (others => <>);
      Statistics.Attempted := 1;
      Statistics.Written := 1;
      return True;
   end App_Success_Fetcher;

   function App_Progress_Fetcher
     (URL              : String;
      Target_Directory : String;
      Statistics       : out Sitefetch.Fetch_Statistics;
      Progress         : Sitefetch.Progress_Callback;
      Options          : Sitefetch.Fetch_Options) return Boolean
   is
   begin
      App_Fetch_Count := App_Fetch_Count + 1;
      Last_App_URL := To_Unbounded_String (URL);
      Last_App_Target := To_Unbounded_String (Target_Directory);
      App_Progress_Was_Null := Progress = null;
      Last_App_Options := Options;

      Statistics := (others => <>);
      Statistics.Attempted := 2;
      Statistics.Written := 1;
      Statistics.Skipped_External := 1;
      return True;
   end App_Progress_Fetcher;

   function App_JSON_Progress_Fetcher
     (URL              : String;
      Target_Directory : String;
      Statistics       : out Sitefetch.Fetch_Statistics;
      Progress         : Sitefetch.Progress_Callback;
      Options          : Sitefetch.Fetch_Options) return Boolean
   is
      pragma Unreferenced (Options);
   begin
      App_Fetch_Count := App_Fetch_Count + 1;
      Last_App_URL := To_Unbounded_String (URL);
      Last_App_Target := To_Unbounded_String (Target_Directory);
      App_Progress_Was_Null := Progress = null;

      if Progress /= null then
         Progress (Sitefetch.Progress_Fetching, URL);
         Progress (Sitefetch.Progress_Written, URL);
         Progress (Sitefetch.Progress_Retry, URL & " (attempt 2 after HTTP_503)");
         Progress (Sitefetch.Progress_Cache_Rejected, URL & "/cache (Vary Accept-Encoding mismatch)");
         Progress (Sitefetch.Progress_Failed, URL & "/bad (network ""down"")");
      end if;

      Statistics := (others => <>);
      Statistics.Attempted := 1;
      Statistics.Written := 1;
      Statistics.Bytes_Written := 42;
      return True;
   end App_JSON_Progress_Fetcher;

   function App_Creating_Fetcher
     (URL              : String;
      Target_Directory : String;
      Statistics       : out Sitefetch.Fetch_Statistics;
      Progress         : Sitefetch.Progress_Callback;
      Options          : Sitefetch.Fetch_Options) return Boolean
   is
      pragma Unreferenced (URL, Progress, Options);
   begin
      App_Fetch_Count := App_Fetch_Count + 1;
      Last_App_Target := To_Unbounded_String (Target_Directory);
      Write_Test_File (Target_Directory & "/index.html", "created target");
      Statistics := (others => <>);
      Statistics.Attempted := 1;
      Statistics.Written := 1;
      return True;
   end App_Creating_Fetcher;

   function App_Failing_Fetcher
     (URL              : String;
      Target_Directory : String;
      Statistics       : out Sitefetch.Fetch_Statistics;
      Progress         : Sitefetch.Progress_Callback;
      Options          : Sitefetch.Fetch_Options) return Boolean
   is
      pragma Unreferenced (URL, Target_Directory, Progress, Options);
   begin
      App_Fetch_Count := App_Fetch_Count + 1;
      Statistics := (others => <>);
      Statistics.Attempted := 2;
      Statistics.Failed := 2;
      Statistics.Failed_URL := To_Unbounded_String ("https://app.example/fail-one");
      Statistics.Failed_Reason := To_Unbounded_String ("APP_FAILURE_ONE");
      Statistics.Failed_Downloads.Append
        (Sitefetch.Failed_Download'
           (URL    => To_Unbounded_String ("https://app.example/fail-one"),
            Reason => To_Unbounded_String ("APP_FAILURE_ONE")));
      Statistics.Failed_Downloads.Append
        (Sitefetch.Failed_Download'
           (URL    => To_Unbounded_String ("https://app.example/fail-two"),
            Reason => To_Unbounded_String ("APP_FAILURE_TWO")));
      return False;
   end App_Failing_Fetcher;

   function App_Raising_Fetcher
     (URL              : String;
      Target_Directory : String;
      Statistics       : out Sitefetch.Fetch_Statistics;
      Progress         : Sitefetch.Progress_Callback;
      Options          : Sitefetch.Fetch_Options) return Boolean
   is
      pragma Unreferenced (URL, Target_Directory, Statistics, Progress, Options);
   begin
      App_Fetch_Count := App_Fetch_Count + 1;
      raise Constraint_Error;
      return False;
   end App_Raising_Fetcher;

   overriding function Name (Item : CLI_Parse_Test) return AUnit.Message_String is
      pragma Unreferenced (Item);
   begin
      return AUnit.Format ("CLI parsing");
   end Name;

   overriding function Name (Item : App_Run_Test) return AUnit.Message_String is
      pragma Unreferenced (Item);
   begin
      return AUnit.Format ("Application runtime");
   end Name;

   overriding function Name (Item : Release_Manifest_Tool_Test) return AUnit.Message_String is
      pragma Unreferenced (Item);
   begin
      return AUnit.Format ("Release manifest tool");
   end Name;

   overriding function Name (Item : Message_Locale_Test) return AUnit.Message_String is
      pragma Unreferenced (Item);
   begin
      return AUnit.Format ("Localized messages");
   end Name;

   overriding function Name (Item : Terminal_Format_Test) return AUnit.Message_String is
      pragma Unreferenced (Item);
   begin
      return AUnit.Format ("Terminal formatting");
   end Name;

   overriding function Name (Item : Catalog_Completeness_Test) return AUnit.Message_String is
      pragma Unreferenced (Item);
   begin
      return AUnit.Format ("Message catalog completeness");
   end Name;

   Fixture_Binary_Body   : constant String := "BINARY-NOEXT";
   Fixture_Redirect_Body : constant String := "REDIRECT-BINARY";
   Fixture_Fallback_Body : constant String := "HEAD-FALLBACK";
   Fixture_Mismatch_Body : constant String := "MISMATCH-BINARY";
   Fixture_SVG_Body      : constant String := "<svg><a href=""/svg-linked"">next</a></svg>";
   Fixture_Font_Body     : constant String := "FONT-NOEXT";
   Fixture_PDF_Body      : constant String := "PDF-NOEXT";
   Fixture_Missing_Body  : constant String := "<a href=""/missing-child"">child</a>";
   Fixture_Reset_Body    : constant String := "RESET-PARTIAL";
   Fixture_Truncated_Body : constant String := "TRUNCATED-PARTIAL";
   Fixture_Write_Fail_Body : constant String := "WRITE-FAIL-BODY";
   Fixture_Flaky_Body   : constant String := "FLAKY-OK";
   Fixture_Cache_Body   : constant String := "CACHE-BINARY";
   Fixture_Text_Lie_Body : constant String := "<a href=""/text-lie-child"">child</a>";
   Fixture_Resume_Body  : constant String := "RESUME-RANGE-BODY";
   Fixture_Changed_Resume_Body : constant String := "CHANGED-RANGE-BODY";
   Fixture_Short_Resume_Body   : constant String := "SHORT-RANGE-BODY";

   function Trimmed_Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   protected type Fixture_Control is
      entry Wait_Ready (Port : out GNAT.Sockets.Port_Type);
      procedure Set_Port (Port : GNAT.Sockets.Port_Type);
      procedure Set_Peer_Port (Port : GNAT.Sockets.Port_Type);
      function Peer_URL return String;
      procedure Stop;
      function Stopped return Boolean;
      procedure Count (Method : String; Path : String);
      function Request_Count (Method : String; Path : String) return Natural;
      function Delay_Child_Count return Natural;
      function Delay_Child_Gap_MS (Index : Positive) return Natural;
      procedure Set_Robots_Fail (Value : Boolean);
      function Robots_Should_Fail return Boolean;
   private
      Ready       : Boolean := False;
      Stop_Flag   : Boolean := False;
      Listen_Port : GNAT.Sockets.Port_Type := 0;
      Peer_Port   : GNAT.Sockets.Port_Type := 0;
      Head_Root   : Natural := 0;
      Get_Root    : Natural := 0;
      Head_Robots : Natural := 0;
      Get_Robots  : Natural := 0;
      Head_Binary : Natural := 0;
      Get_Binary  : Natural := 0;
      Head_Redirect : Natural := 0;
      Get_Redirect  : Natural := 0;
      Head_Final    : Natural := 0;
      Get_Final     : Natural := 0;
      Head_405      : Natural := 0;
      Get_405       : Natural := 0;
      Head_Mismatch : Natural := 0;
      Get_Mismatch  : Natural := 0;
      Head_Big      : Natural := 0;
      Get_Big       : Natural := 0;
      Head_Flaky    : Natural := 0;
      Get_Flaky     : Natural := 0;
      Head_Status_Transient : Natural := 0;
      Get_Status_Transient  : Natural := 0;
      Head_Status_Permanent : Natural := 0;
      Get_Status_Permanent  : Natural := 0;
      Head_Structured_Status : Natural := 0;
      Get_Structured_Status  : Natural := 0;
      Head_Resume   : Natural := 0;
      Get_Resume    : Natural := 0;
      Head_Cross_Loop_B : Natural := 0;
      Get_Cross_Loop_B  : Natural := 0;
      Delay_Children : Natural := 0;
      Delay_Child_1  : Ada.Calendar.Time := Ada.Calendar.Time_Of (1901, 1, 1);
      Delay_Child_2  : Ada.Calendar.Time := Ada.Calendar.Time_Of (1901, 1, 1);
      Delay_Child_3  : Ada.Calendar.Time := Ada.Calendar.Time_Of (1901, 1, 1);
      Robots_Fail   : Boolean := False;
   end Fixture_Control;

   protected body Fixture_Control is
      entry Wait_Ready (Port : out GNAT.Sockets.Port_Type) when Ready is
      begin
         Port := Listen_Port;
      end Wait_Ready;

      procedure Set_Port (Port : GNAT.Sockets.Port_Type) is
      begin
         Listen_Port := Port;
         Ready := True;
      end Set_Port;

      procedure Set_Peer_Port (Port : GNAT.Sockets.Port_Type) is
      begin
         Peer_Port := Port;
      end Set_Peer_Port;

      function Peer_URL return String is
      begin
         return "http://127.0.0.1:" & Trimmed_Image (Natural (Peer_Port));
      end Peer_URL;

      procedure Stop is
      begin
         Stop_Flag := True;
      end Stop;

      function Stopped return Boolean is
      begin
         return Stop_Flag;
      end Stopped;

      procedure Count (Method : String; Path : String) is
      begin
         if Method = "HEAD" and then Path = "/" then
            Head_Root := Head_Root + 1;
         elsif Method = "GET" and then Path = "/" then
            Get_Root := Get_Root + 1;
         elsif Method = "HEAD" and then Path = "/robots.txt" then
            Head_Robots := Head_Robots + 1;
         elsif Method = "GET" and then Path = "/robots.txt" then
            Get_Robots := Get_Robots + 1;
         elsif Method = "HEAD" and then Path = "/binary" then
            Head_Binary := Head_Binary + 1;
         elsif Method = "GET" and then Path = "/binary" then
            Get_Binary := Get_Binary + 1;
         elsif Method = "HEAD" and then Path = "/redirect-bin" then
            Head_Redirect := Head_Redirect + 1;
         elsif Method = "GET" and then Path = "/redirect-bin" then
            Get_Redirect := Get_Redirect + 1;
         elsif Method = "HEAD" and then Path = "/final.bin" then
            Head_Final := Head_Final + 1;
         elsif Method = "GET" and then Path = "/final.bin" then
            Get_Final := Get_Final + 1;
         elsif Method = "HEAD" and then Path = "/head-405" then
            Head_405 := Head_405 + 1;
         elsif Method = "GET" and then Path = "/head-405" then
            Get_405 := Get_405 + 1;
         elsif Method = "HEAD" and then Path = "/mismatch" then
            Head_Mismatch := Head_Mismatch + 1;
         elsif Method = "GET" and then Path = "/mismatch" then
            Get_Mismatch := Get_Mismatch + 1;
         elsif Method = "HEAD" and then Path = "/big" then
            Head_Big := Head_Big + 1;
         elsif Method = "GET" and then Path = "/big" then
            Get_Big := Get_Big + 1;
         elsif Method = "HEAD" and then Path = "/flaky.bin" then
            Head_Flaky := Head_Flaky + 1;
         elsif Method = "GET" and then Path = "/flaky.bin" then
            Get_Flaky := Get_Flaky + 1;
         elsif Method = "HEAD" and then Path = "/status-transient.bin" then
            Head_Status_Transient := Head_Status_Transient + 1;
         elsif Method = "GET" and then Path = "/status-transient.bin" then
            Get_Status_Transient := Get_Status_Transient + 1;
         elsif Method = "HEAD" and then Path = "/status-permanent.bin" then
            Head_Status_Permanent := Head_Status_Permanent + 1;
         elsif Method = "GET" and then Path = "/status-permanent.bin" then
            Get_Status_Permanent := Get_Status_Permanent + 1;
         elsif Method = "HEAD" and then Path = "/structured-status-transient.bin" then
            Head_Structured_Status := Head_Structured_Status + 1;
         elsif Method = "GET" and then Path = "/structured-status-transient.bin" then
            Get_Structured_Status := Get_Structured_Status + 1;
         elsif Method = "HEAD" and then Path = "/resume.bin" then
            Head_Resume := Head_Resume + 1;
         elsif Method = "GET" and then Path = "/resume.bin" then
            Get_Resume := Get_Resume + 1;
         elsif Method = "HEAD" and then Path = "/cross-loop-b.bin" then
            Head_Cross_Loop_B := Head_Cross_Loop_B + 1;
         elsif Method = "GET" and then Path = "/cross-loop-b.bin" then
            Get_Cross_Loop_B := Get_Cross_Loop_B + 1;
         elsif Method = "GET"
           and then Path in "/delay-child-1.html" | "/delay-child-2.html" | "/delay-child-3.html"
         then
            Delay_Children := Delay_Children + 1;
            if Delay_Children = 1 then
               Delay_Child_1 := Ada.Calendar.Clock;
            elsif Delay_Children = 2 then
               Delay_Child_2 := Ada.Calendar.Clock;
            elsif Delay_Children = 3 then
               Delay_Child_3 := Ada.Calendar.Clock;
            end if;
         end if;
      end Count;

      procedure Set_Robots_Fail (Value : Boolean) is
      begin
         Robots_Fail := Value;
      end Set_Robots_Fail;

      function Robots_Should_Fail return Boolean is
      begin
         return Robots_Fail;
      end Robots_Should_Fail;

      function Request_Count (Method : String; Path : String) return Natural is
      begin
         if Method = "HEAD" and then Path = "/" then
            return Head_Root;
         elsif Method = "GET" and then Path = "/" then
            return Get_Root;
         elsif Method = "HEAD" and then Path = "/robots.txt" then
            return Head_Robots;
         elsif Method = "GET" and then Path = "/robots.txt" then
            return Get_Robots;
         elsif Method = "HEAD" and then Path = "/binary" then
            return Head_Binary;
         elsif Method = "GET" and then Path = "/binary" then
            return Get_Binary;
         elsif Method = "HEAD" and then Path = "/redirect-bin" then
            return Head_Redirect;
         elsif Method = "GET" and then Path = "/redirect-bin" then
            return Get_Redirect;
         elsif Method = "HEAD" and then Path = "/final.bin" then
            return Head_Final;
         elsif Method = "GET" and then Path = "/final.bin" then
            return Get_Final;
         elsif Method = "HEAD" and then Path = "/head-405" then
            return Head_405;
         elsif Method = "GET" and then Path = "/head-405" then
            return Get_405;
         elsif Method = "HEAD" and then Path = "/mismatch" then
            return Head_Mismatch;
         elsif Method = "GET" and then Path = "/mismatch" then
            return Get_Mismatch;
         elsif Method = "HEAD" and then Path = "/big" then
            return Head_Big;
         elsif Method = "GET" and then Path = "/big" then
            return Get_Big;
         elsif Method = "HEAD" and then Path = "/flaky.bin" then
            return Head_Flaky;
         elsif Method = "GET" and then Path = "/flaky.bin" then
            return Get_Flaky;
         elsif Method = "HEAD" and then Path = "/status-transient.bin" then
            return Head_Status_Transient;
         elsif Method = "GET" and then Path = "/status-transient.bin" then
            return Get_Status_Transient;
         elsif Method = "HEAD" and then Path = "/status-permanent.bin" then
            return Head_Status_Permanent;
         elsif Method = "GET" and then Path = "/status-permanent.bin" then
            return Get_Status_Permanent;
         elsif Method = "HEAD" and then Path = "/structured-status-transient.bin" then
            return Head_Structured_Status;
         elsif Method = "GET" and then Path = "/structured-status-transient.bin" then
            return Get_Structured_Status;
         elsif Method = "HEAD" and then Path = "/resume.bin" then
            return Head_Resume;
         elsif Method = "GET" and then Path = "/resume.bin" then
            return Get_Resume;
         elsif Method = "HEAD" and then Path = "/cross-loop-b.bin" then
            return Head_Cross_Loop_B;
         elsif Method = "GET" and then Path = "/cross-loop-b.bin" then
            return Get_Cross_Loop_B;
         else
            return 0;
         end if;
      end Request_Count;

      function Delay_Child_Count return Natural is
      begin
         return Delay_Children;
      end Delay_Child_Count;

      function Delay_Child_Gap_MS (Index : Positive) return Natural is
         Gap : Duration := 0.0;
      begin
         if Index = 1 and then Delay_Children >= 2 then
            Gap := Delay_Child_2 - Delay_Child_1;
         elsif Index = 2 and then Delay_Children >= 3 then
            Gap := Delay_Child_3 - Delay_Child_2;
         end if;

         if Gap <= 0.0 then
            return 0;
         else
            return Natural (Long_Float (Gap) * 1000.0);
         end if;
      end Delay_Child_Gap_MS;
   end Fixture_Control;

   task type Fixture_Server (Control : not null access Fixture_Control);

   task body Fixture_Server is
      use type Ada.Streams.Stream_Element_Offset;
      use type GNAT.Sockets.Selector_Status;

      CRLF : constant String := Character'Val (13) & Character'Val (10);
      Root_Body : constant String :=
        "<a href=""/binary"">binary</a><a href=""/redirect-bin"">redirect</a>"
        & "<a href=""/head-405"">fallback</a><a href=""/mismatch"">mismatch</a>"
        & "<a href=""/icon.svg"">svg</a><a href=""/fontfile"">font</a>"
        & "<a href=""/pdf-doc"">pdf</a><a href=""/missing-type"">missing</a>";
      Robots_Root_Body : constant String :=
        "<a href=""/robots-allowed.html"">allowed</a>"
        & "<a href=""/robots-blocked.html"">blocked</a>"
        & "<a href=""/robots-private/allowed.html"">allowed private</a>"
        & "<a href=""/robots-private/blocked.html"">blocked private</a>"
        & "<a href=""/robots-wild/blocked.tmp"">wild blocked</a>"
        & "<a href=""/robots-wild/allowed.txt"">wild allowed</a>"
        & "<a href=""/robots-anchor/exact"">anchor blocked</a>"
        & "<a href=""/robots-anchor/exactly"">anchor allowed</a>";
      Redirected_Robots_Root_Body : constant String :=
        "<a href=""/robots-allowed.html"">allowed</a>"
        & "<a href=""/robots-blocked.html"">blocked</a>";
      Robots_Body : constant String :=
        "User-agent: other" & Character'Val (10)
        & "Disallow: /" & Character'Val (10)
        & Character'Val (10)
        & "User-agent: sitefetch-test" & Character'Val (10)
        & "Disallow: /robots-blocked.html" & Character'Val (10)
        & "Disallow: /robots-private" & Character'Val (10)
        & "Allow: /robots-private/allowed.html" & Character'Val (10)
        & "Disallow: /robots-wild/*.tmp" & Character'Val (10)
        & "Disallow: /robots-anchor/exact$" & Character'Val (10)
        & "Crawl-delay: 0" & Character'Val (10)
        & "Sitemap: /robots-sitemap.xml" & Character'Val (10)
        & Character'Val (10)
        & "User-agent: *" & Character'Val (10)
        & "Disallow: /robots-allowed.html" & Character'Val (10);
      Cache_Root_Body : constant String := "<a href=""/cache-child.html"">child</a>";
      Delay_Root_Body : constant String :=
        "<a href=""/delay-child-1.html"">one</a>"
        & "<a href=""/delay-child-2.html"">two</a>"
        & "<a href=""/delay-child-3.html"">three</a>";
      Malformed_CSS_Body : constant String :=
        ".bad{background:url('/malformed-css-a.png'}"
        & ".next{background:url(""/malformed-css-b.png"")}"
        & "/* url(/ignored-malformed-css.png) */";
      Malformed_Sitemap_Body : constant String :=
        "<?xml version=""1.0""?><urlset>"
        & "<url><loc>/malformed-sitemap-before.html</loc>"
        & "<!-- <loc>/ignored-malformed-sitemap.html</loc> -->"
        & "<url><loc>/malformed-sitemap-after.html</loc></url>"
        & "<url><loc>/malformed-sitemap-unclosed.html";
      Binary_Body   : String renames Fixture_Binary_Body;
      Redirect_Body : String renames Fixture_Redirect_Body;
      Fallback_Body : String renames Fixture_Fallback_Body;
      Mismatch_Body : String renames Fixture_Mismatch_Body;
      SVG_Body      : String renames Fixture_SVG_Body;
      Font_Body     : String renames Fixture_Font_Body;
      PDF_Body      : String renames Fixture_PDF_Body;
      Missing_Body  : String renames Fixture_Missing_Body;
      Big_Body      : constant String := "0123456789AB";
      Resume_Body   : String renames Fixture_Resume_Body;
      Changed_Resume_Body : String renames Fixture_Changed_Resume_Body;
      Short_Resume_Body   : String renames Fixture_Short_Resume_Body;
      Server        : GNAT.Sockets.Socket_Type;
      Client        : GNAT.Sockets.Socket_Type;
      Address       : GNAT.Sockets.Sock_Addr_Type;
      Peer          : GNAT.Sockets.Sock_Addr_Type;
      Status        : GNAT.Sockets.Selector_Status;
      Idle_Count    : Natural := 0;

      function Trimmed_Image (Value : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

      function Request_Text (Socket : GNAT.Sockets.Socket_Type) return String is
         Buffer : Ada.Streams.Stream_Element_Array (1 .. 4096);
         Last   : Ada.Streams.Stream_Element_Offset;
         Result : Unbounded_String := Null_Unbounded_String;
      begin
         GNAT.Sockets.Receive_Socket (Socket, Buffer, Last);
         for Index in Buffer'First .. Last loop
            Append (Result, Character'Val (Integer (Buffer (Index))));
         end loop;
         return To_String (Result);
      end Request_Text;

      function Request_Method (Request : String) return String is
      begin
         for Index in Request'Range loop
            if Request (Index) = ' ' then
               return Request (Request'First .. Index - 1);
            end if;
         end loop;
         return "";
      end Request_Method;

      function Request_Path (Request : String) return String is
         First_Space  : Natural := 0;
         Second_Space : Natural := 0;
      begin
         for Index in Request'Range loop
            if Request (Index) = ' ' then
               if First_Space = 0 then
                  First_Space := Index;
               else
                  Second_Space := Index;
                  exit;
               end if;
            end if;
         end loop;

         if First_Space = 0 or else Second_Space <= First_Space + 1 then
            return "";
         else
            return Request (First_Space + 1 .. Second_Space - 1);
         end if;
      end Request_Path;

      procedure Send_Text (Socket : GNAT.Sockets.Socket_Type; Text : String) is
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         for Index in Text'Range loop
            Data (Ada.Streams.Stream_Element_Offset (Index - Text'First + 1)) :=
              Ada.Streams.Stream_Element (Character'Pos (Text (Index)));
         end loop;
         GNAT.Sockets.Send_Socket (Socket, Data, Last);
      end Send_Text;

      procedure Respond
        (Socket       : GNAT.Sockets.Socket_Type;
         Method       : String;
         Status_Line  : String;
         Content_Type : String;
         Body_Text    : String;
         Extra        : String := "")
      is
         Headers : Unbounded_String := To_Unbounded_String
           (Status_Line & CRLF
            & "Content-Length: " & Trimmed_Image (Body_Text'Length) & CRLF
            & "Connection: close" & CRLF);
      begin
         if Content_Type /= "" then
            Append (Headers, "Content-Type: " & Content_Type & CRLF);
         end if;
         if Extra /= "" then
            Append (Headers, Extra);
         end if;
         Append (Headers, CRLF);
         if Method /= "HEAD" then
            Append (Headers, Body_Text);
         end if;
         Send_Text (Socket, To_String (Headers));
      end Respond;

      function To_Zlib_Bytes (Text : String) return Zlib.Byte_Array is
         Result : Zlib.Byte_Array (0 .. Text'Length - 1);
      begin
         for Offset in Result'Range loop
            Result (Offset) := Zlib.Byte (Character'Pos (Text (Text'First + Offset)));
         end loop;
         return Result;
      end To_Zlib_Bytes;

      function To_Binary_String (Bytes : Zlib.Byte_Array) return String is
         Result : String (1 .. Bytes'Length);
         Index  : Positive := Result'First;
      begin
         for Item of Bytes loop
            Result (Index) := Character'Val (Natural (Item));
            Index := Index + 1;
         end loop;
         return Result;
      end To_Binary_String;

      function GZip_Text (Text : String) return String is
         Status : Zlib.Status_Code;
         Bytes  : constant Zlib.Byte_Array := Zlib.GZip (To_Zlib_Bytes (Text), Zlib.Stored, Status);
      begin
         Assert (Status = Zlib.Ok, "gzip fixture generation succeeds");
         return To_Binary_String (Bytes);
      end GZip_Text;

      procedure Respond_Short_Body
        (Socket          : GNAT.Sockets.Socket_Type;
         Method          : String;
         Body_Text       : String;
         Declared_Length : Natural)
      is
         Response : Unbounded_String := To_Unbounded_String
           ("HTTP/1.1 200 OK" & CRLF
            & "Content-Type: application/octet-stream" & CRLF
            & "Content-Length: " & Trimmed_Image (Declared_Length) & CRLF
            & "Connection: close" & CRLF & CRLF);
      begin
         if Method /= "HEAD" then
            Append (Response, Body_Text);
         end if;
         Send_Text (Socket, To_String (Response));
      end Respond_Short_Body;

      procedure Respond_Broken_Chunk
        (Socket    : GNAT.Sockets.Socket_Type;
         Method    : String;
         Body_Text : String)
      is
         Response : Unbounded_String := To_Unbounded_String
           ("HTTP/1.1 200 OK" & CRLF
            & "Content-Type: application/octet-stream" & CRLF
            & "Transfer-Encoding: chunked" & CRLF
            & "Connection: close" & CRLF & CRLF);
      begin
         if Method /= "HEAD" then
            Append (Response, "20" & CRLF & Body_Text);
         end if;
         Send_Text (Socket, To_String (Response));
      end Respond_Broken_Chunk;

      procedure Respond_Broken_Chunk_With_Extra
        (Socket    : GNAT.Sockets.Socket_Type;
         Method    : String;
         Body_Text : String;
         Extra     : String)
      is
         Response : Unbounded_String := To_Unbounded_String
           ("HTTP/1.1 200 OK" & CRLF
            & "Content-Type: application/octet-stream" & CRLF
            & "Transfer-Encoding: chunked" & CRLF
            & Extra
            & "Connection: close" & CRLF & CRLF);
      begin
         if Method /= "HEAD" then
            Append (Response, "20" & CRLF & Body_Text);
         end if;
         Send_Text (Socket, To_String (Response));
      end Respond_Broken_Chunk_With_Extra;

      procedure Respond_Range
        (Socket    : GNAT.Sockets.Socket_Type;
         Method    : String;
         Body_Text : String;
         Request   : String)
      is
         Range_Pos : constant Natural := Ada.Strings.Fixed.Index (Request, "Range: bytes=");
         Start_Pos : Natural := 0;
         End_Pos   : Natural := 0;
         Start     : Natural := 0;
      begin
         if Range_Pos > 0 then
            Start_Pos := Range_Pos + 13;
            End_Pos := Start_Pos;
            while End_Pos <= Request'Last and then Request (End_Pos) in '0' .. '9' loop
               End_Pos := End_Pos + 1;
            end loop;
            if End_Pos > Start_Pos then
               Start := Natural'Value (Request (Start_Pos .. End_Pos - 1));
            end if;
         end if;

         if Range_Pos > 0 and then Start < Body_Text'Length then
            declare
               Chunk : constant String := Body_Text (Body_Text'First + Start .. Body_Text'Last);
               Last_Byte : constant Natural := Body_Text'Length - 1;
            begin
               declare
                  Response : Unbounded_String := To_Unbounded_String
                    ("HTTP/1.1 206 Partial Content" & CRLF
                     & "Content-Range: bytes " & Trimmed_Image (Start) & "-"
                     & Trimmed_Image (Last_Byte) & "/" & Trimmed_Image (Body_Text'Length)
                     & CRLF & CRLF);
               begin
                  if Method /= "HEAD" then
                     Append (Response, Chunk);
                  end if;
                  Send_Text (Socket, To_String (Response));
               end;
            end;
         else
            Respond
              (Socket,
               Method,
               "HTTP/1.1 200 OK",
               "application/octet-stream",
               Body_Text,
               "ETag: resume-v1" & CRLF);
         end if;
      end Respond_Range;

      procedure Respond_Range_Or_416
        (Socket    : GNAT.Sockets.Socket_Type;
         Method    : String;
         Body_Text : String;
         Request   : String)
      is
         Range_Pos : constant Natural := Ada.Strings.Fixed.Index (Request, "Range: bytes=");
         Start_Pos : Natural := 0;
         End_Pos   : Natural := 0;
         Start     : Natural := 0;
      begin
         if Range_Pos > 0 then
            Start_Pos := Range_Pos + 13;
            End_Pos := Start_Pos;
            while End_Pos <= Request'Last and then Request (End_Pos) in '0' .. '9' loop
               End_Pos := End_Pos + 1;
            end loop;
            if End_Pos > Start_Pos then
               Start := Natural'Value (Request (Start_Pos .. End_Pos - 1));
            end if;
         end if;

         if Range_Pos > 0 and then Start >= Body_Text'Length then
            Respond
              (Socket, Method, "HTTP/1.1 416 Range Not Satisfiable", "", "",
               "Content-Range: bytes */" & Trimmed_Image (Body_Text'Length) & CRLF);
         else
            Respond_Range (Socket, Method, Body_Text, Request);
         end if;
      end Respond_Range_Or_416;

      procedure Respond_If_Range_Changed
        (Socket    : GNAT.Sockets.Socket_Type;
         Method    : String;
         Body_Text : String;
         Request   : String)
      is
      begin
         if Ada.Strings.Fixed.Index (Request, "Range: bytes=") > 0
           and then Ada.Strings.Fixed.Index (Request, "If-Range: old-resume-v1") > 0
         then
            Respond
              (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream", Body_Text,
               "ETag: changed-resume-v2" & CRLF);
         else
            Respond_Range (Socket, Method, Body_Text, Request);
         end if;
      end Respond_If_Range_Changed;


      procedure Handle (Socket : GNAT.Sockets.Socket_Type) is
         Request : constant String := Request_Text (Socket);
         Method  : constant String := Request_Method (Request);
         Path    : constant String := Request_Path (Request);
      begin
         Control.Count (Method, Path);
         if Path = "/" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", Root_Body);
         elsif Path = "/robots.txt" and then Control.Robots_Should_Fail then
            Respond (Socket, Method, "HTTP/1.1 503 Service Unavailable", "text/plain", "robots unavailable");
         elsif Path = "/robots.txt" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/plain", Robots_Body);
         elsif Path = "/robots-root.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", Robots_Root_Body);
         elsif Path = "/redirect-to-peer-robots.html" then
            Respond
              (Socket, Method, "HTTP/1.1 302 Found", "", "",
               "Location: " & Control.Peer_URL & "/redirected-robots-root.html" & CRLF);
         elsif Path = "/redirected-robots-root.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", Redirected_Robots_Root_Body);
         elsif Path = "/robots-allowed.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "allowed");
         elsif Path = "/robots-blocked.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "blocked");
         elsif Path = "/robots-private/allowed.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "allowed private");
         elsif Path = "/robots-private/blocked.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "blocked private");
         elsif Path = "/robots-wild/blocked.tmp" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "wild blocked");
         elsif Path = "/robots-wild/allowed.txt" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "wild allowed");
         elsif Path = "/robots-anchor/exact" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "anchor blocked");
         elsif Path = "/robots-anchor/exactly" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "anchor allowed");
         elsif Path = "/robots-sitemap.xml" then
            Respond
              (Socket,
               Method,
               "HTTP/1.1 200 OK",
               "application/xml",
               "<?xml version=""1.0""?><urlset>"
               & "<url><loc>/robots-sitemap-child.html</loc></url>"
               & "<url><loc>/robots-sitemap-level-2.xml</loc></url>"
               & "<url><loc>/robots-sitemap-compressed.xml.gz</loc></url>"
               & "</urlset>");
         elsif Path = "/robots-sitemap-compressed.xml.gz" then
            Respond
              (Socket, Method, "HTTP/1.1 200 OK", "application/gzip",
               GZip_Text
                 ("<?xml version=""1.0""?><urlset>"
                  & "<url><loc>/robots-sitemap-gzip-child.html</loc></url>"
                  & "</urlset>"));
         elsif Path = "/robots-sitemap-gzip-child.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "gzip sitemap child");
         elsif Path = "/robots-sitemap-level-2.xml" then
            Respond
              (Socket,
               Method,
               "HTTP/1.1 200 OK",
               "application/xml",
               "<?xml version=""1.0""?><urlset>"
               & "<url><loc>/robots-sitemap-depth-page.html</loc></url>"
               & "<url><loc>/robots-sitemap-level-3.xml</loc></url>"
               & "</urlset>");
         elsif Path = "/robots-sitemap-level-3.xml" then
            Respond
              (Socket, Method, "HTTP/1.1 200 OK", "application/xml",
               "<?xml version=""1.0""?><urlset><url><loc>/robots-sitemap-too-deep.html</loc></url></urlset>");
         elsif Path = "/robots-sitemap-depth-page.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "sitemap depth page");
         elsif Path = "/robots-sitemap-too-deep.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "too deep");
         elsif Path = "/robots-sitemap-child.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "sitemap child");
         elsif Path = "/cache-root.html"
           and then Ada.Strings.Fixed.Index (Request, "If-None-Match: cache-root-v1") > 0
         then
            Respond (Socket, Method, "HTTP/1.1 304 Not Modified", "", "", "ETag: cache-root-v1" & CRLF);
         elsif Path = "/cache-root.html" then
            Respond
              (Socket, Method, "HTTP/1.1 200 OK", "text/html", Cache_Root_Body,
               "ETag: cache-root-v1" & CRLF
               & "Cache-Control: max-age=60" & CRLF
               & "Expires: Wed, 21 Oct 2037 07:28:00 GMT" & CRLF);
         elsif Path = "/cache-child.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "cache child");
         elsif Path = "/delay-root.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", Delay_Root_Body);
         elsif Path in "/delay-child-1.html" | "/delay-child-2.html" | "/delay-child-3.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "delay child");
         elsif Path = "/malformed.css" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/css", Malformed_CSS_Body);
         elsif Path = "/malformed-css-a.png" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "image/png", "CSS-A");
         elsif Path = "/malformed-css-b.png" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "image/png", "CSS-B");
         elsif Path = "/ignored-malformed-css.png" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "image/png", "CSS-IGNORED");
         elsif Path = "/malformed-sitemap.xml" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/xml", Malformed_Sitemap_Body);
         elsif Path = "/malformed-sitemap-before.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "sitemap before");
         elsif Path = "/malformed-sitemap-after.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "sitemap after");
         elsif Path = "/malformed-sitemap-unclosed.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "sitemap unclosed");
         elsif Path = "/ignored-malformed-sitemap.html" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "sitemap ignored");
         elsif Path = "/cache-must.html"
           and then Ada.Strings.Fixed.Index (Request, "If-None-Match: cache-must-v1") > 0
         then
            Respond (Socket, Method, "HTTP/1.1 304 Not Modified", "", "", "ETag: cache-must-v1" & CRLF);
         elsif Path = "/cache-must.html" then
            Respond
              (Socket, Method, "HTTP/1.1 200 OK", "text/html", "must cache",
               "ETag: cache-must-v1" & CRLF
               & "Cache-Control: max-age=3600, must-revalidate" & CRLF);
         elsif Path = "/cache-stale-no-validator.html" then
            Respond
              (Socket, Method, "HTTP/1.1 200 OK", "text/html", "stale cache",
               "Cache-Control: max-age=0" & CRLF);
         elsif Path = "/cache-vary-lang.html" then
            Respond
              (Socket, Method, "HTTP/1.1 200 OK", "text/html", "vary lang",
               "ETag: cache-vary-lang-v1" & CRLF
               & "Cache-Control: max-age=3600" & CRLF
               & "Vary: Accept-Language" & CRLF);
         elsif Path = "/cache-vary-combo.html" then
            Respond
              (Socket, Method, "HTTP/1.1 200 OK", "text/html", "vary combo",
               "ETag: cache-vary-combo-v1" & CRLF
               & "Cache-Control: max-age=3600" & CRLF
               & "Vary: Accept-Language, Accept-Encoding" & CRLF);
         elsif Path = "/cache.bin" and then Method = "HEAD"
           and then Ada.Strings.Fixed.Index (Request, "If-None-Match: cache-bin-v1") > 0
         then
            Respond
              (Socket, Method, "HTTP/1.1 304 Not Modified", "", "",
               "ETag: cache-bin-v1" & CRLF);
         elsif Path = "/cache.bin" then
            Respond
              (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream",
               Fixture_Cache_Body,
               "ETag: cache-bin-v1" & CRLF
               & "Cache-Control: max-age=60" & CRLF
               & "Expires: Wed, 21 Oct 2037 07:28:00 GMT" & CRLF
               & "Vary: User-Agent" & CRLF);
         elsif Path = "/resume.bin" then
            Respond_Range (Socket, Method, Resume_Body, Request);
         elsif Path = "/resume-changed.bin" then
            Respond_If_Range_Changed (Socket, Method, Changed_Resume_Body, Request);
         elsif Path = "/resume-416-complete.bin" then
            Respond_Range_Or_416 (Socket, Method, Resume_Body, Request);
         elsif Path = "/resume-oversized.bin" then
            Respond_Range_Or_416 (Socket, Method, Short_Resume_Body, Request);
         elsif Path = "/binary" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream", Binary_Body);
         elsif Path = "/redirect-bin" then
            Respond
              (Socket, Method, "HTTP/1.1 302 Found", "", "",
               "Location: /final.bin" & CRLF);
         elsif Path = "/redirect-hop-1" then
            Respond
              (Socket, Method, "HTTP/1.1 302 Found", "", "",
               "Location: /redirect-hop-2" & CRLF);
         elsif Path = "/redirect-hop-2" then
            Respond
              (Socket, Method, "HTTP/1.1 301 Moved Permanently", "", "",
               "Location: /final.bin" & CRLF);
         elsif Path = "/redirect-page-hop-1" then
            Respond
              (Socket, Method, "HTTP/1.1 302 Found", "", "",
               "Location: /redirect-page-hop-2" & CRLF);
         elsif Path = "/redirect-page-hop-2" then
            Respond
              (Socket, Method, "HTTP/1.1 301 Moved Permanently", "", "",
               "Location: /redirect-final.html" & CRLF);
         elsif Path = "/redirect-final.html" then
            Respond
              (Socket, Method, "HTTP/1.1 200 OK", "text/html",
               "<html><body>redirect final</body></html>");
         elsif Path = "/loop-a" then
            Respond
              (Socket, Method, "HTTP/1.1 302 Found", "", "",
               "Location: /loop-b" & CRLF);
         elsif Path = "/loop-b" then
            Respond
              (Socket, Method, "HTTP/1.1 302 Found", "", "",
               "Location: /loop-a" & CRLF);
         elsif Path = "/cross-loop-a.bin" then
            Respond
              (Socket, Method, "HTTP/1.1 302 Found", "", "",
               "Location: " & Control.Peer_URL & "/cross-loop-b.bin" & CRLF);
         elsif Path = "/cross-loop-b.bin" then
            Respond
              (Socket, Method, "HTTP/1.1 302 Found", "", "",
               "Location: " & Control.Peer_URL & "/cross-loop-a.bin" & CRLF);
         elsif Path = "/final.bin" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream", Redirect_Body);
         elsif Path = "/head-405" and then Method = "HEAD" then
            Respond (Socket, Method, "HTTP/1.1 405 Method Not Allowed", "", "");
         elsif Path = "/head-405" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "image/png", Fallback_Body);
         elsif Path = "/mismatch" and then Method = "HEAD" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "");
         elsif Path = "/mismatch" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream", Mismatch_Body);
         elsif Path = "/text-lie" and then Method = "HEAD" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream", "");
         elsif Path = "/text-lie" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", Fixture_Text_Lie_Body);
         elsif Path = "/text-lie-child" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "text lie child");
         elsif Path = "/icon.svg" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "image/svg+xml", SVG_Body);
         elsif Path = "/svg-linked" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "svg child");
         elsif Path = "/fontfile" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "font/woff2", Font_Body);
         elsif Path = "/pdf-doc" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/pdf", PDF_Body);
         elsif Path = "/missing-type" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "", Missing_Body);
         elsif Path = "/missing-child" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "text/html", "missing child");
         elsif Path = "/reset.bin" then
            Respond_Broken_Chunk (Socket, Method, Fixture_Reset_Body);
         elsif Path = "/truncated.bin" then
            Respond_Short_Body (Socket, Method, Fixture_Truncated_Body, Fixture_Truncated_Body'Length + 16);
         elsif Path = "/redirect-to-failure.bin" then
            Respond
              (Socket, Method, "HTTP/1.1 302 Found", "", "",
               "Location: /truncated.bin" & CRLF);
         elsif Path = "/blocked/file.bin" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream", Fixture_Write_Fail_Body);
         elsif Path = "/partial-strong.bin" then
            Respond_Broken_Chunk_With_Extra
              (Socket, Method, Fixture_Reset_Body, "ETag: partial-strong-v1" & CRLF);
         elsif Path = "/partial-weak.bin" then
            Respond_Broken_Chunk_With_Extra
              (Socket, Method, Fixture_Reset_Body, "ETag: W/""partial-weak-v1""" & CRLF);
         elsif Path = "/flaky.bin" and then Control.Request_Count ("GET", "/flaky.bin") = 1 then
            Respond_Broken_Chunk (Socket, Method, Fixture_Reset_Body);
         elsif Path = "/flaky.bin" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream", Fixture_Flaky_Body);
         elsif Path = "/status-transient.bin"
           and then Control.Request_Count ("GET", "/status-transient.bin") = 1
         then
            Respond
              (Socket, Method, "HTTP/1.1 503 Service Unavailable",
               "application/octet-stream", "temporary unavailable");
         elsif Path = "/status-transient.bin" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream", "STATUS-OK");
         elsif Path = "/structured-status-transient.bin"
           and then Control.Request_Count ("GET", "/structured-status-transient.bin") = 1
         then
            Respond
              (Socket, Method, "HTTP/1.1 503 Service Unavailable",
               "application/octet-stream", "temporary unavailable");
         elsif Path = "/structured-status-transient.bin" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream", "STRUCTURED-OK");
         elsif Path = "/status-permanent.bin" then
            Respond (Socket, Method, "HTTP/1.1 404 Not Found", "application/octet-stream", "missing forever");
         elsif Path = "/big" then
            Respond (Socket, Method, "HTTP/1.1 200 OK", "application/octet-stream", Big_Body);
         else
            Respond (Socket, Method, "HTTP/1.1 404 Not Found", "text/plain", "missing");
         end if;
      end Handle;
   begin
      GNAT.Sockets.Initialize;
      GNAT.Sockets.Create_Socket (Server);
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Address.Port := 0;
      GNAT.Sockets.Bind_Socket (Server, Address);
      GNAT.Sockets.Listen_Socket (Server);
      Control.Set_Port (GNAT.Sockets.Get_Socket_Name (Server).Port);

      loop
         exit when Control.Stopped;
         GNAT.Sockets.Accept_Socket (Server, Client, Peer, 0.20, Status => Status);
         if Status = GNAT.Sockets.Completed then
            Idle_Count := 0;
            begin
               Handle (Client);
            exception
               when others =>
                  null;
            end;
            GNAT.Sockets.Close_Socket (Client);
         else
            Idle_Count := Idle_Count + 1;
            exit when Idle_Count > 25;
         end if;
      end loop;

      GNAT.Sockets.Close_Socket (Server);
   exception
      when others =>
         Control.Stop;
   end Fixture_Server;

   overriding procedure Run_Test (Item : in out CLI_Parse_Test) is
      use type Sitefetch.CLI.Parse_Status;
      use type Sitefetch.Safety_Mode;
      use type Sitefetch.Domain_Policy;
      use type Sitefetch.Head_Policy;
      use type Sitefetch.Robots_Policy;
      use type Sitefetch.Robots_Failure_Policy;
      use type Sitefetch.Cache_Mode;
      use type Sitefetch.Cache_Resource_Strategy;
      use type Sitefetch.Cache_Hash_Algorithm;
      use type Sitefetch.Diagnostics_Mode;
      use type Sitefetch.Write_Durability_Mode;
      pragma Unreferenced (Item);
   begin
      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--quiet"),
            To_Unbounded_String ("--locale"),
            To_Unbounded_String ("de_DE.UTF-8"),
            To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Ok, "ordinary arguments parse");
         Assert (Options.Quiet, "quiet option is retained");
         Assert (Options.Locale_Provided, "locale option is retained");
         Assert (To_String (Options.Locale) = "de_DE.UTF-8", "locale value is retained");
         Assert (To_String (Options.Source_URL) = "example.com", "source URL is retained");
         Assert
           (Options.Limits.Crawl.Max_Pages = Sitefetch.Default_Fetch_Options.Crawl.Max_Pages,
            "default max pages retained");
         Assert (Options.Limits.Crawl.Max_Depth = 0, "default max depth retained");
         Assert (Options.Limits.Crawl.Workers = Sitefetch.Default_Worker_Count, "default worker count retained");
         Assert (Options.Limits.Crawl.Max_Per_Host_Connections = 0, "default per-host cap is disabled");
         Assert (Options.Limits.Crawl.Robots_Failure = Sitefetch.Robots_Fail_Open, "default robots failure is open");
         Assert (Options.Limits.HTTP.Max_Retries = 0, "default retry count retained");
         Assert (Options.Limits.HTTP.Retry_Delay_MS = 0, "default retry delay retained");
         Assert (Options.Limits.HTTP.Retry_Jitter_MS = 0, "default retry jitter retained");
         Assert (Length (Options.Limits.HTTP.Accept_Language) = 0, "default Accept-Language is unset");
         Assert
           (To_String (Options.Limits.HTTP.Accept_Encoding) = Sitefetch.Default_Accept_Encoding,
            "default Accept-Encoding is retained");
         Assert (not Options.JSONL_Output, "default JSONL output is disabled");
         Assert (not Options.JSON_Summary, "default JSON summary output is disabled");
         Assert (not Options.Limits.Cache.Require_Metadata_Version,
                 "default cache metadata version requirement is disabled");
         Assert (Options.Limits.Cache.Verify_Local_Content,
                 "default cache local verification is enabled");
         Assert
           (Options.Limits.Cache.Resource_Strategy = Sitefetch.Cache_All_Resources,
            "default cache resource strategy covers all resources");
         Assert
           (Options.Limits.Cache.Hash_Algorithm = Sitefetch.Cache_Hash_FNV1a_64,
            "default cache hash algorithm is FNV1a-64");
         Assert (Options.Limits.Safety.Mode = Sitefetch.Safety_Default, "default safety mode retained");
         Assert
           (Options.Limits.Safety.Write_Durability = Sitefetch.Write_Durability_Default,
            "default write durability is normal");
         Assert
           (Options.Limits.Diagnostics.Mode = Sitefetch.Diagnostics_Quiet,
            "default diagnostics policy is quiet");
         Assert
           (Options.Limits.Crawl.Domain = Sitefetch.Domain_Exact_And_Subdomains,
            "default domain policy is strict");
         Assert
           (Options.Limits.HTTP.Head = Sitefetch.Head_Page_Like,
            "default HEAD policy probes page-like candidates");
         Assert (To_String (Options.Target_Directory) = ".", "default target is current directory");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--max-pages"),
            To_Unbounded_String ("12"),
            To_Unbounded_String ("--max-depth=3"),
            To_Unbounded_String ("--max-bytes=4096"),
            To_Unbounded_String ("--max-failures=2"),
            To_Unbounded_String ("--workers=16"),
            To_Unbounded_String ("--max-per-host=2"),
            To_Unbounded_String ("--robots-fail-closed"),
            To_Unbounded_String ("--retries=3"),
            To_Unbounded_String ("--retry-delay-ms=25"),
            To_Unbounded_String ("--retry-jitter-ms=6"),
            To_Unbounded_String ("--request-delay-ms=7"),
            To_Unbounded_String ("--jsonl"),
            To_Unbounded_String ("--json-summary"),
            To_Unbounded_String ("--robots"),
            To_Unbounded_String ("--cache=offline"),
            To_Unbounded_String ("--cache-max-stale-ms=5000"),
            To_Unbounded_String ("--cache-vary-accept-language"),
            To_Unbounded_String ("--cache-vary-accept-encoding"),
            To_Unbounded_String ("--cache-require-version"),
            To_Unbounded_String ("--cache-no-verify-local"),
            To_Unbounded_String ("--cache-hash=none"),
            To_Unbounded_String ("--cache-downloads-only"),
            To_Unbounded_String ("--verbose"),
            To_Unbounded_String ("--durable-writes"),
            To_Unbounded_String ("--user-agent=sitefetch-test"),
            To_Unbounded_String ("--accept-language=da-DK"),
            To_Unbounded_String ("--accept-encoding=identity"),
            To_Unbounded_String ("--skip-dangerous"),
            To_Unbounded_String ("--head=ambiguous"),
            To_Unbounded_String ("--include-parent-domains"),
            To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Ok, "crawl limit options parse");
         Assert (Options.Limits.Crawl.Max_Pages = 12, "max pages option is retained");
         Assert (Options.Limits.Crawl.Max_Depth = 3, "max depth option is retained");
         Assert (Options.Limits.Crawl.Max_Bytes = 4_096, "max bytes option is retained");
         Assert (Options.Limits.Crawl.Max_Failures = 2, "max failures option is retained");
         Assert (Options.Limits.Crawl.Workers = 16, "workers option is retained");
         Assert (Options.Limits.Crawl.Max_Per_Host_Connections = 2, "per-host cap option is retained");
         Assert (Options.Limits.Crawl.Robots_Failure = Sitefetch.Robots_Fail_Closed,
                 "robots fail-closed option is retained");
         Assert (Options.Limits.HTTP.Max_Retries = 3, "retry option is retained");
         Assert (Options.Limits.HTTP.Retry_Delay_MS = 25, "retry delay option is retained");
         Assert (Options.Limits.HTTP.Retry_Jitter_MS = 6, "retry jitter option is retained");
         Assert (Options.Limits.HTTP.Request_Delay_MS = 7, "request delay option is retained");
         Assert (Options.JSONL_Output, "JSONL option is retained");
         Assert (Options.JSON_Summary, "JSON summary option is retained");
         Assert (Options.Limits.Crawl.Robots = Sitefetch.Robots_Respect, "robots option is retained");
         Assert (Options.Limits.Cache.Mode = Sitefetch.Cache_Offline, "offline cache option is retained");
         Assert (Options.Limits.Cache.Max_Stale_MS = 5_000, "cache max-stale option is retained");
         Assert (Options.Limits.Cache.Vary_Allow.Accept_Language, "cache Vary Accept-Language allow is retained");
         Assert (Options.Limits.Cache.Vary_Allow.Accept_Encoding, "cache Vary Accept-Encoding allow is retained");
         Assert (Options.Limits.Cache.Require_Metadata_Version,
                 "cache metadata version requirement option is retained");
         Assert (not Options.Limits.Cache.Verify_Local_Content,
                 "cache local verification opt-out is retained");
         Assert
           (Options.Limits.Cache.Hash_Algorithm = Sitefetch.Cache_Hash_None,
            "cache hash option is retained");
         Assert
           (Options.Limits.Cache.Resource_Strategy = Sitefetch.Cache_Downloads_Only,
            "cache resource strategy option is retained");
         Assert (Options.Verbose, "verbose option is retained");
         Assert
           (Options.Limits.Diagnostics.Mode = Sitefetch.Diagnostics_Verbose,
            "verbose option enables diagnostics policy");
         Assert (To_String (Options.Limits.HTTP.User_Agent) = "sitefetch-test", "user-agent option is retained");
         Assert (To_String (Options.Limits.HTTP.Accept_Language) = "da-DK", "accept-language option is retained");
         Assert (To_String (Options.Limits.HTTP.Accept_Encoding) = "identity", "accept-encoding option is retained");
         Assert (Options.Limits.Safety.Mode = Sitefetch.Safety_Skip_Dangerous, "skip-dangerous is retained");
         Assert
           (Options.Limits.Safety.Write_Durability = Sitefetch.Write_Durability_Sync_Data_And_Directory,
            "durable writes option is retained");
         Assert
           (Options.Limits.Crawl.Domain = Sitefetch.Domain_Include_Parents,
            "parent-domain option is retained");
         Assert
           (Options.Limits.HTTP.Head = Sitefetch.Head_Ambiguous_Only,
            "ambiguous HEAD policy option is retained");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--safe"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Ok, "safe mode parses");
         Assert
           (Options.Limits.Safety.Mode = Sitefetch.Safety_Assets_Only_Safe,
            "safe mode is retained");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--assets-only-safe"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Ok, "assets-only-safe mode parses");
         Assert
           (Options.Limits.Safety.Mode = Sitefetch.Safety_Assets_Only_Safe,
            "assets-only-safe mode is retained");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--head"),
            To_Unbounded_String ("off"),
            To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Ok, "separate HEAD policy option parses");
         Assert (Options.Limits.HTTP.Head = Sitefetch.Head_Disabled, "separate HEAD policy is retained");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--cache-hash"),
            To_Unbounded_String ("sha256"),
            To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Ok, "separate cache hash option parses");
         Assert
           (Options.Limits.Cache.Hash_Algorithm = Sitefetch.Cache_Hash_SHA256,
            "separate SHA-256 cache hash option is retained");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--cache"),
            To_Unbounded_String ("refresh"),
            To_Unbounded_String ("--retry-jitter-ms"),
            To_Unbounded_String ("9"),
            To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Ok, "separate cache mode and retry jitter options parse");
         Assert
           (Options.Limits.Cache.Mode = Sitefetch.Cache_Refresh,
            "separate cache mode option is retained");
         Assert
           (Options.Limits.HTTP.Retry_Jitter_MS = 9,
            "separate retry jitter option is retained");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--no-head"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Ok, "no-head option parses");
         Assert (Options.Limits.HTTP.Head = Sitefetch.Head_Disabled, "no-head disables HEAD policy");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--locale=fr_FR.UTF-8"), To_Unbounded_String ("--help")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Show_Help, "help request is retained");
         Assert (Options.Locale_Provided, "help can still carry locale");
         Assert (To_String (Options.Locale) = "fr_FR.UTF-8", "equals-form locale is retained");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--locale")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Error, "missing locale is an error");
         Assert (To_String (Options.Error_Key) = "error.locale_missing", "missing locale key is reported");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--locale=")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Error, "empty locale is an error");
         Assert (To_String (Options.Error_Key) = "error.locale_empty", "empty locale key is reported");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--workers=0"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Error, "zero workers is an error");
         Assert (To_String (Options.Error_Key) = "error.unknown_option", "zero workers reports an error");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--workers=65"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Error, "too many workers is an error");
         Assert (To_String (Options.Error_Key) = "error.unknown_option", "too many workers reports an error");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--bad")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Error, "unknown option is an error");
         Assert (To_String (Options.Error_Key) = "error.unknown_option", "unknown option key is reported");
         Assert (To_String (Options.Error_Arg_Key) = "option", "unknown option argument key is retained");
         Assert (To_String (Options.Error_Arg_Value) = "--bad", "unknown option value is retained");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("url"), To_Unbounded_String ("target"), To_Unbounded_String ("extra")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Error, "third positional argument is an error");
         Assert (To_String (Options.Error_Key) = "error.too_many_arguments", "too many arguments key is used");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array := [1 => To_Unbounded_String ("-h")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Show_Help, "short help option is accepted");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array := [1 => To_Unbounded_String ("--version")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Show_Version, "version option is accepted");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("-q"), To_Unbounded_String ("url"), To_Unbounded_String ("target")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
      begin
         Assert (Options.Status = Sitefetch.CLI.Parse_Ok, "short quiet option parses with target");
         Assert (Options.Quiet, "short quiet option is retained");
         Assert (To_String (Options.Target_Directory) = "target", "target positional value is retained");
      end;
   end Run_Test;

   overriding procedure Run_Test (Item : in out App_Run_Test) is
      use type Sitefetch.App.Exit_Status;
      use type Sitefetch.Safety_Mode;
      pragma Unreferenced (Item);
   begin
      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--quiet"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Success_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Success, "quiet successful fetch exits successfully");
         Assert (App_Fetch_Count = 1, "quiet successful fetch calls fetcher once");
         Assert (App_Progress_Was_Null, "quiet successful fetch disables progress callback");
         Assert
           (Last_App_Options.Crawl.Max_Pages = Sitefetch.Default_Fetch_Options.Crawl.Max_Pages,
            "default max pages passed");
         Assert (Last_App_Options.Crawl.Max_Depth = 0, "default max depth passed");
         Assert (Output_Count = 0, "quiet successful fetch suppresses ordinary output");
         Assert (Error_Count = 0, "quiet successful fetch has no diagnostic output");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--locale=de_DE.UTF-8"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Success_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Success, "localized successful fetch exits successfully");
         Assert (Output_Count > 0, "localized successful fetch writes ordinary output");
         Assert (Sitefetch.Messages.Current_Locale = "de-de", "application runtime applies locale option");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array := [1 => To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
         LC_All_Found : constant Boolean := Ada.Environment_Variables.Exists ("LC_ALL");
         LC_All_Value : Unbounded_String := Null_Unbounded_String;
      begin
         if LC_All_Found then
            LC_All_Value := To_Unbounded_String (Ada.Environment_Variables.Value ("LC_ALL"));
         end if;

         Ada.Environment_Variables.Set ("LC_ALL", "it_IT.UTF-8");
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Success_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Success, "system locale successful fetch exits successfully");
         Assert (Sitefetch.Messages.Current_Locale = "it-it", "application runtime detects system locale");
         Assert (Captured_Output_Has ("completato"), "system locale affects rendered app output");

         if LC_All_Found then
            Ada.Environment_Variables.Set ("LC_ALL", To_String (LC_All_Value));
         else
            Ada.Environment_Variables.Clear ("LC_ALL");
         end if;
      exception
         when others =>
            if LC_All_Found then
               Ada.Environment_Variables.Set ("LC_ALL", To_String (LC_All_Value));
            else
               Ada.Environment_Variables.Clear ("LC_ALL");
            end if;
            raise;
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--locale=en"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Progress_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Success, "progress fetch exits successfully");
         Assert (not App_Progress_Was_Null, "non-quiet successful fetch enables progress callback");
         Assert (Captured_Output_Has ("fetching: http://example.com"), "start URL is printed");
         Assert (Captured_Output_Has ("target:   ."), "target summary is printed");
         Assert (Captured_Output_Has ("completed"), "success status is printed");
         Assert (Captured_Output_Has ("attempted: 2"), "attempted summary is printed");
         Assert (Captured_Output_Has ("written:   1"), "written summary is printed");
         Assert (Captured_Output_Has ("external:  1"), "external summary is printed");
         Assert (Captured_Output_Has ("failed:   0"), "failed summary is printed");
         Assert (Captured_Output_Has ("elapsed:"), "elapsed summary is printed");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--json-summary"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Success_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Success, "JSON summary successful fetch exits successfully");
         Assert (Captured_Output_Has ("{""type"":""summary"""), "JSON summary type is emitted");
         Assert (Captured_Output_Has ("""success"":true"), "JSON summary success is emitted");
         Assert (Captured_Output_Has ("""attempted"":1"), "JSON summary attempted count is emitted");
         Assert (Captured_Output_Has ("""written"""), "JSON summary written count is emitted");
         Assert
           (Captured_Output_Has ("""skipped_external"""),
            "JSON summary external skip count is emitted");
         Assert
           (Captured_Output_Has ("""skipped_unsupported"""),
            "JSON summary unsupported skip count is emitted");
         Assert
           (Captured_Output_Has ("""skipped_limit"""),
            "JSON summary limit skip count is emitted");
         Assert
           (Captured_Output_Has ("""bytes_written"""),
            "JSON summary bytes written count is emitted");
         Assert (Captured_Output_Has ("""failed"""), "JSON summary failed count is emitted");
         Assert (Captured_Output_Has ("""retries"":0"), "JSON summary retry count is emitted");
         Assert (Captured_Output_Has ("""cache_hits"":0"), "JSON summary cache hit count is emitted");
         Assert (Captured_Output_Has ("""cache_revalidations"":0"), "JSON summary cache revalidation count is emitted");
         Assert (Captured_Output_Has ("""cache_rejections"":0"), "JSON summary cache rejection count is emitted");
         Assert
           (Captured_Output_Has ("""cache_rejection_reasons"":{}"),
            "JSON summary empty cache rejection reasons object is emitted");
         Assert (Captured_Output_Has ("""robots_allowed"":0"), "JSON summary robots allowed count is emitted");
         Assert (Captured_Output_Has ("""robots_disallowed"":0"), "JSON summary robots disallowed count is emitted");
         Assert (Captured_Output_Has ("""robots_loaded"":0"), "JSON summary robots loaded count is emitted");
         Assert (Captured_Output_Has ("""robots_failed"":0"), "JSON summary robots failed count is emitted");
         Assert (Captured_Output_Has ("""redirects"":0"), "JSON summary redirect count is emitted");
         Assert (Captured_Output_Has ("""redirect_hops"":0"), "JSON summary redirect hop count is emitted");
         Assert (Captured_Output_Has ("""elapsed_seconds"""), "JSON summary elapsed seconds is emitted");
         Assert (Captured_Output_Has ("""failed_url"":"), "JSON summary failed URL is emitted");
         Assert
           (Captured_Output_Has ("""failed_reason"""),
            "JSON summary failed reason is emitted");
         Assert (Captured_Output_Has ("""failed_download_count"":0"),
                 "JSON summary failed download count is emitted");
         Assert (Captured_Output_Has ("""failed_downloads"":[]"),
                 "JSON summary failed download list is emitted");
         Assert (not Captured_Output_Has ("completed"), "JSON summary suppresses human summary");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--jsonl"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_JSON_Progress_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Success, "JSONL successful fetch exits successfully");
         Assert (not App_Progress_Was_Null, "JSONL fetch receives JSON progress callback");
         Assert
           (Captured_Output_Has ("{""type"":""progress"",""event"":""fetching"""),
            "JSONL progress event is emitted");
         Assert
           (Captured_Output_Has ("""event"":""failed"",""url"":""example.com/bad"""),
            "JSONL progress separates reason-bearing URLs");
         Assert
           (Captured_Output_Has ("""reason"":""network \""down\"""""),
            "JSONL progress emits escaped reason field");
         Assert
           (Captured_Output_Has ("""local_path"":"""""),
            "JSONL progress emits local path field");
         Assert
           (Captured_Output_Has ("""bytes_written"""),
            "JSONL progress emits bytes written field");
         Assert
           (Captured_Output_Has ("""depth"":0"),
            "JSONL progress emits depth field");
         Assert
           (Captured_Output_Has ("""retry_attempt"":2"),
            "JSONL progress emits retry attempt field");
         Assert
           (Captured_Output_Has ("""status_code"":503"),
            "JSONL progress emits status code field");
         Assert
           (Captured_Output_Has ("""cache_decision"":"""""),
            "JSONL progress emits cache decision field");
         Assert
           (Captured_Output_Has ("""event"":""cache_rejected"",""url"":""example.com/cache"""),
            "JSONL progress emits cache rejection event");
         Assert
           (Captured_Output_Has ("""reason"":""Vary Accept-Encoding mismatch"""),
            "JSONL progress emits cache rejection reason");
         Assert
           (Captured_Output_Has ("""cache_decision"":""rejected"""),
            "JSONL progress emits rejected cache decision");
         Assert
           (Captured_Output_Has ("""robots_source"":"""""),
            "JSONL progress emits robots source field");
         Assert
           (Captured_Output_Has ("""final_url"":"""""),
            "JSONL progress emits final URL field");
         Assert
           (Captured_Output_Has ("""source_id"":"""""),
            "JSONL progress emits source id field");
         Assert
           (Captured_Output_Has ("""redirect_hops"":0"),
            "JSONL progress emits redirect hop count field");
         Assert
           (Captured_Output_Has ("""redirect_chain"":"""""),
            "JSONL progress emits redirect chain field");
         Assert
           (Captured_Output_Has ("{""type"":""summary"",""success"":true"),
            "JSONL final summary is emitted");
         Assert
           (Captured_Output_Has ("""retries"":1"),
            "JSONL final summary counts retries");
         Assert
           (Captured_Output_Has ("""cache_rejections"":1"),
            "JSONL final summary counts cache rejections");
         Assert
           (Captured_Output_Has
              ("""cache_rejection_reasons"":{""Vary Accept-Encoding mismatch"":1}"),
            "JSONL final summary counts cache rejection reasons");
         Assert
           (Captured_Output_Has ("""failed_downloads"":[]"),
            "JSONL final summary emits failed download list");
         Assert (not Captured_Output_Has ("fetching: http://example.com"), "JSONL suppresses human start line");
      end;

      declare
         Target : constant String := "test-output-app-jsonl-production-cache";
         Control : aliased Fixture_Control;
         Server  : Fixture_Server (Control'Access);
         Port    : GNAT.Sockets.Port_Type;
         URL     : Unbounded_String;
      begin
         Control.Wait_Ready (Port);
         URL := To_Unbounded_String
           ("http://127.0.0.1:" & Trimmed_Image (Natural (Port)) & "/cache-stale-no-validator.html");
         Delete_Tree_If_Present (Target);

         declare
            Warm_Statistics : Sitefetch.Fetch_Statistics;
            Warm_Limits     : Sitefetch.Fetch_Options := Sitefetch.Default_Fetch_Options;
         begin
            Warm_Limits.Crawl.Workers := 1;
            Warm_Limits.Cache.Mode := Sitefetch.Cache_Revalidate;
            Assert
              (Sitefetch.Crawler.Fetch_Website
                 (To_String (URL), Target, Warm_Statistics, null, Warm_Limits),
               "production JSONL cache fixture warms stale no-validator cache");
         end;

         declare
            Args : constant Sitefetch.CLI.Argument_Array :=
              [To_Unbounded_String ("--jsonl"),
               To_Unbounded_String ("--verbose"),
               To_Unbounded_String ("--revalidate-cache"),
               To_Unbounded_String (To_String (URL)),
               To_Unbounded_String (Target)];
            Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
            Status  : Sitefetch.App.Exit_Status;
         begin
            Reset_App_Fake;
            Status := Sitefetch.App.Run (Options, Record_Output'Access, Record_Error'Access);
            Assert (Status = Sitefetch.App.Exit_Success, "production JSONL cache rejection exits successfully");
            Assert
              (Captured_Output_Has ("""event"":""cache_rejected"""),
               "production JSONL emits cache rejection event");
            Assert
              (Captured_Output_Has ("""reason"":""cache stale without validators"""),
               "production JSONL emits stale cache rejection reason");
            Assert
              (Captured_Output_Has ("""cache_decision"":""rejected"""),
               "production JSONL emits rejected cache decision");
            Assert
              (Captured_Output_Has ("""cache_rejections"":1"),
               "production JSONL final summary counts real cache rejection");
         end;

         Control.Stop;
         Delete_Tree_If_Present (Target);
      exception
         when others =>
            Control.Stop;
            Delete_Tree_If_Present (Target);
            raise;
      end;

      declare
         Target : constant String := "test-output-app-jsonl-production-cache-offline";
         Control : aliased Fixture_Control;
         Server  : Fixture_Server (Control'Access);
         Port    : GNAT.Sockets.Port_Type;
         URL     : Unbounded_String;
      begin
         Control.Wait_Ready (Port);
         URL := To_Unbounded_String
           ("http://127.0.0.1:" & Trimmed_Image (Natural (Port)) & "/cache-stale-no-validator.html");
         Delete_Tree_If_Present (Target);

         declare
            Warm_Statistics : Sitefetch.Fetch_Statistics;
            Warm_Limits     : Sitefetch.Fetch_Options := Sitefetch.Default_Fetch_Options;
         begin
            Warm_Limits.Crawl.Workers := 1;
            Warm_Limits.Cache.Mode := Sitefetch.Cache_Revalidate;
            Assert
              (Sitefetch.Crawler.Fetch_Website
                 (To_String (URL), Target, Warm_Statistics, null, Warm_Limits),
               "production JSONL offline cache fixture warms stale no-validator cache");
         end;

         declare
            Args : constant Sitefetch.CLI.Argument_Array :=
              [To_Unbounded_String ("--jsonl"),
               To_Unbounded_String ("--verbose"),
               To_Unbounded_String ("--offline-cache"),
               To_Unbounded_String (To_String (URL)),
               To_Unbounded_String (Target)];
            Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
            Status  : Sitefetch.App.Exit_Status;
         begin
            Reset_App_Fake;
            Status := Sitefetch.App.Run (Options, Record_Output'Access, Record_Error'Access);
            Assert (Status = Sitefetch.App.Exit_Failure, "production JSONL offline stale cache exits with failure");
            Assert
              (Captured_Output_Has ("""event"":""cache_rejected"""),
               "production JSONL offline emits cache rejection event");
            Assert
              (Captured_Output_Has ("""reason"":""offline cache entry stale"""),
               "production JSONL offline emits stale cache rejection reason");
            Assert
              (Captured_Output_Has ("""cache_decision"":""rejected"""),
               "production JSONL offline emits rejected cache decision");
            Assert
              (Captured_Output_Has ("""success"":false"),
               "production JSONL offline final summary reports failure");
            Assert
              (Captured_Output_Has ("""cache_rejections"":1"),
               "production JSONL offline final summary counts real cache rejection");
         end;

         Control.Stop;
         Delete_Tree_If_Present (Target);
      exception
         when others =>
            Control.Stop;
            Delete_Tree_If_Present (Target);
            raise;
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--max-pages=9"), To_Unbounded_String ("--workers"),
            To_Unbounded_String ("11"), To_Unbounded_String ("--safe"), To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Success_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Success, "limited successful fetch exits successfully");
         Assert (Last_App_Options.Crawl.Max_Pages = 9, "app passes max pages to fetcher");
         Assert (Last_App_Options.Crawl.Workers = 11, "app passes worker count to fetcher");
         Assert
           (Last_App_Options.Safety.Mode = Sitefetch.Safety_Assets_Only_Safe,
            "app passes safety mode to fetcher");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array := [1 => To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Failing_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Failure, "failed fetch exits with failure");
         Assert (Error_Count > 0, "failed fetch writes diagnostic output");
         Assert (To_String (Last_Error_Line) /= "", "failed fetch records diagnostic text");
         Assert (Captured_Error_Has ("https://app.example/fail-one"), "first failed URL is listed");
         Assert (Captured_Error_Has ("https://app.example/fail-two"), "second failed URL is listed");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("example.com"), To_Unbounded_String ("")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Success_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Failure, "empty target exits with failure");
         Assert (App_Fetch_Count = 0, "empty target is rejected before fetching");
         Assert (Error_Count > 0, "empty target writes diagnostic output");
      end;

      declare
         Target : constant String := "test-output-app-created-target";
         Args   : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("--locale=en"), To_Unbounded_String ("example.com"), To_Unbounded_String (Target)];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Delete_Tree_If_Present (Target);
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Creating_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Success, "missing target directory can be created by fetcher");
         Assert (Ada.Directories.Exists (Target & "/index.html"), "created target contains fetched file");
         Delete_Tree_If_Present (Target);
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array := [1 => To_Unbounded_String ("--bad")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Success_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Failure, "parse error exits with failure");
         Assert (App_Fetch_Count = 0, "parse error does not call fetcher");
         Assert (Output_Count > 0, "parse error prints usage output");
         Assert (Error_Count > 0, "parse error prints diagnostic output");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array := [1 => To_Unbounded_String ("--help")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Success_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Success, "help exits successfully");
         Assert (App_Fetch_Count = 0, "help does not call fetcher");
         Assert (Output_Count > 0, "help prints usage output");
         Assert (Error_Count = 0, "help has no diagnostic output");
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array := [1 => To_Unbounded_String ("--version")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Success_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Success, "version exits successfully");
         Assert (App_Fetch_Count = 0, "version does not call fetcher");
         Assert (Output_Count > 0, "version prints output");
         Assert (Error_Count = 0, "version has no diagnostic output");
      end;

      declare
         Target : constant String := "test-output-target-file";
         Args   : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("example.com"), To_Unbounded_String (Target)];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Delete_Tree_If_Present (Target);
         Write_Test_File (Target, "not a directory");
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Success_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Failure, "file target exits with failure");
         Assert (App_Fetch_Count = 0, "file target is rejected before fetching");
         Assert (Error_Count > 0, "file target writes diagnostic output");
         Ada.Directories.Delete_File (Target);
      end;

      declare
         Args : constant Sitefetch.CLI.Argument_Array := [1 => To_Unbounded_String ("example.com")];
         Options : constant Sitefetch.CLI.Parsed_Options := Sitefetch.CLI.Parse (Args);
         Status  : Sitefetch.App.Exit_Status;
      begin
         Reset_App_Fake;
         Status := Sitefetch.App.Run
           (Options, App_Raising_Fetcher'Access, Record_Output'Access, Record_Error'Access);
         Assert (Status = Sitefetch.App.Exit_Failure, "fetch exception exits with failure");
         Assert (App_Fetch_Count = 1, "fetch exception path calls fetcher once");
         Assert (Error_Count > 0, "fetch exception writes diagnostic output");
      end;

      Sitefetch.Messages.Set_Locale ("en");
   end Run_Test;

   overriding procedure Run_Test (Item : in out Message_Locale_Test) is
      pragma Unreferenced (Item);
      LC_All_Found      : Boolean;
      LC_Messages_Found : Boolean;
      Lang_Found        : Boolean;
      LC_All_Value      : Unbounded_String;
      LC_Messages_Value : Unbounded_String;
      Lang_Value        : Unbounded_String;
   begin
      Sitefetch.Messages.Set_Locale ("de_DE.UTF-8");
      Assert (Sitefetch.Messages.Current_Locale = "de-de", "locale is normalized");
      Assert
        (Sitefetch.Messages.Text ("status.completed") = "abgeschlossen",
         "regional locale falls back to base language");

      Sitefetch.Messages.Set_Locale ("C");
      Assert (Sitefetch.Messages.Current_Locale = "en", "C locale maps to English");
      Assert (Sitefetch.Messages.Text ("status.completed") = "completed", "English fallback renders");
      Sitefetch.Messages.Set_Locale ("zz_ZZ.UTF-8");
      Assert (Sitefetch.Messages.Current_Locale = "zz-zz", "unsupported locale is normalized");
      Assert
        (Sitefetch.Messages.Text ("status.completed") = "completed",
         "unsupported locale falls back to English");
      Assert
        (Sitefetch.Messages.Text ("missing.key") = "missing.key",
         "unknown message key falls back to the key name");

      declare
         Modern_Locales : constant Sitefetch.CLI.Argument_Array :=
           [To_Unbounded_String ("en"), To_Unbounded_String ("hi_Latn"),
            To_Unbounded_String ("nn"), To_Unbounded_String ("ar"),
            To_Unbounded_String ("cy"), To_Unbounded_String ("ga"),
            To_Unbounded_String ("he"), To_Unbounded_String ("pl"),
            To_Unbounded_String ("lt"), To_Unbounded_String ("cs"),
            To_Unbounded_String ("sk"), To_Unbounded_String ("sl"),
            To_Unbounded_String ("ru"), To_Unbounded_String ("uk"),
            To_Unbounded_String ("hsb"), To_Unbounded_String ("be"),
            To_Unbounded_String ("ja"), To_Unbounded_String ("sr"),
            To_Unbounded_String ("sr_Latn"), To_Unbounded_String ("dsb"),
            To_Unbounded_String ("ta"), To_Unbounded_String ("az"),
            To_Unbounded_String ("ro"), To_Unbounded_String ("hr"),
            To_Unbounded_String ("lv"), To_Unbounded_String ("pa"),
            To_Unbounded_String ("bs"), To_Unbounded_String ("fa"),
            To_Unbounded_String ("uz"), To_Unbounded_String ("ur"),
            To_Unbounded_String ("bn"), To_Unbounded_String ("fr"),
            To_Unbounded_String ("ps"), To_Unbounded_String ("kk"),
            To_Unbounded_String ("ml"), To_Unbounded_String ("pt"),
            To_Unbounded_String ("tr"), To_Unbounded_String ("hi"),
            To_Unbounded_String ("mr"), To_Unbounded_String ("ne"),
            To_Unbounded_String ("ha"), To_Unbounded_String ("am"),
            To_Unbounded_String ("sq"), To_Unbounded_String ("tk"),
            To_Unbounded_String ("mn"), To_Unbounded_String ("kok"),
            To_Unbounded_String ("gu"), To_Unbounded_String ("kn"),
            To_Unbounded_String ("te"), To_Unbounded_String ("es"),
            To_Unbounded_String ("fi"), To_Unbounded_String ("as"),
            To_Unbounded_String ("or"), To_Unbounded_String ("ca"),
            To_Unbounded_String ("bg"), To_Unbounded_String ("ky"),
            To_Unbounded_String ("de"), To_Unbounded_String ("zh_Hant"),
            To_Unbounded_String ("hu"), To_Unbounded_String ("gl"),
            To_Unbounded_String ("zh"), To_Unbounded_String ("sv"),
            To_Unbounded_String ("it"), To_Unbounded_String ("da"),
            To_Unbounded_String ("si"), To_Unbounded_String ("mk"),
            To_Unbounded_String ("et"), To_Unbounded_String ("nl"),
            To_Unbounded_String ("sw"), To_Unbounded_String ("fil"),
            To_Unbounded_String ("el"), To_Unbounded_String ("hy"),
            To_Unbounded_String ("ka"), To_Unbounded_String ("is"),
            To_Unbounded_String ("no"), To_Unbounded_String ("zu"),
            To_Unbounded_String ("ms"), To_Unbounded_String ("af"),
            To_Unbounded_String ("ko"), To_Unbounded_String ("chr"),
            To_Unbounded_String ("id"), To_Unbounded_String ("th"),
            To_Unbounded_String ("gd"), To_Unbounded_String ("my"),
            To_Unbounded_String ("lo"), To_Unbounded_String ("km"),
            To_Unbounded_String ("vi"), To_Unbounded_String ("yo"),
            To_Unbounded_String ("ig"), To_Unbounded_String ("sd"),
            To_Unbounded_String ("so"), To_Unbounded_String ("eu"),
            To_Unbounded_String ("yue"), To_Unbounded_String ("yue_Hans"),
            To_Unbounded_String ("pcm"), To_Unbounded_String ("jv"),
            To_Unbounded_String ("qu")];
      begin
         for Locale_Name of Modern_Locales loop
            Sitefetch.Messages.Set_Locale (To_String (Locale_Name) & ".UTF-8");
            Assert
              (Sitefetch.Messages.Text ("status.completed") /= "status.completed",
               "CLDR modern locale renders with fallback: " & To_String (Locale_Name));
         end loop;
      end;

      Sitefetch.Messages.Set_Locale ("zh_Hant.UTF-8");
      declare
         Parent_Text : constant String := Sitefetch.Messages.Text ("status.completed");
      begin
         Sitefetch.Messages.Set_Locale ("zh_Hant_TW.UTF-8");
         Assert
           (Sitefetch.Messages.Current_Locale = "zh-hant-tw",
            "script and region locale is normalized");
         Assert
           (Sitefetch.Messages.Text ("status.completed") = Parent_Text,
            "script and region locale falls back through parent subtags");
      end;

      Sitefetch.Messages.Set_Locale ("C");
      Assert
        (Sitefetch.Messages.Text ("summary.failed", "count", "2") = "failed:   2",
         "English failed count summary substitutes count");
      Assert
        (Sitefetch.Messages.Text ("status.failed_reason", "reason", "HPACK_HUFFMAN_ERROR")
         = "failed: HPACK_HUFFMAN_ERROR",
         "English failed status substitutes reason");

      Sitefetch.Messages.Set_Locale ("fr_FR.UTF-8");
      Assert (Sitefetch.Messages.Text ("status.completed") = "terminé", "French status renders");
      Assert
        (Sitefetch.Messages.Text ("status.failed_reason", "reason", "BROKEN_DOWNLOAD")
         = "échec: BROKEN_DOWNLOAD",
         "French failed status substitutes reason");

      Sitefetch.Messages.Set_Locale ("es_ES.UTF-8");
      Assert (Sitefetch.Messages.Text ("status.completed") = "completado", "Spanish status renders");
      Assert
        (Sitefetch.Messages.Text ("status.failed_reason", "reason", "BROKEN_DOWNLOAD")
         = "fallido: BROKEN_DOWNLOAD",
         "Spanish failed status substitutes reason");

      Sitefetch.Messages.Set_Locale ("ru_RU.UTF-8");
      Assert (Sitefetch.Messages.Text ("status.completed") = "завершено", "Russian status renders");
      Assert
        (Sitefetch.Messages.Text ("status.failed_reason", "reason", "BROKEN_DOWNLOAD")
         = "сбой: BROKEN_DOWNLOAD",
         "Russian failed status substitutes reason");

      Save_Environment ("LC_ALL", LC_All_Found, LC_All_Value);
      Save_Environment ("LC_MESSAGES", LC_Messages_Found, LC_Messages_Value);
      Save_Environment ("LANG", Lang_Found, Lang_Value);

      begin
         Ada.Environment_Variables.Set ("LC_ALL", "pl_PL.UTF-8");
         Ada.Environment_Variables.Set ("LC_MESSAGES", "de_DE.UTF-8");
         Ada.Environment_Variables.Set ("LANG", "fr_FR.UTF-8");
         Sitefetch.Messages.Detect_System_Locale;
         Assert (Sitefetch.Messages.Current_Locale = "pl-pl", "LC_ALL has locale precedence");
         Assert (Sitefetch.Messages.Text ("status.completed") = "ukończono", "LC_ALL locale renders");

         Ada.Environment_Variables.Clear ("LC_ALL");
         Sitefetch.Messages.Detect_System_Locale;
         Assert (Sitefetch.Messages.Current_Locale = "de-de", "LC_MESSAGES is second locale source");

         Ada.Environment_Variables.Clear ("LC_MESSAGES");
         Sitefetch.Messages.Detect_System_Locale;
         Assert (Sitefetch.Messages.Current_Locale = "fr-fr", "LANG is third locale source");
      exception
         when others =>
            Restore_Environment ("LC_ALL", LC_All_Found, LC_All_Value);
            Restore_Environment ("LC_MESSAGES", LC_Messages_Found, LC_Messages_Value);
            Restore_Environment ("LANG", Lang_Found, Lang_Value);
            raise;
      end;

      Restore_Environment ("LC_ALL", LC_All_Found, LC_All_Value);
      Restore_Environment ("LC_MESSAGES", LC_Messages_Found, LC_Messages_Value);
      Restore_Environment ("LANG", Lang_Found, Lang_Value);
      Sitefetch.Messages.Set_Locale ("en");
   end Run_Test;

   overriding procedure Run_Test (Item : in out Terminal_Format_Test) is
      pragma Unreferenced (Item);
      No_Color_Found : Boolean;
      No_Color_Value : Unbounded_String;
      Saved_Policy   : constant Terminal_Styles.Color_Policy := Terminal_Styles.Current_Color_Policy;

      function Has_Prefix (Item : String; Prefix : String) return Boolean is
      begin
         return Item'Length >= Prefix'Length
           and then Item (Item'First .. Item'First + Prefix'Length - 1) = Prefix;
      end Has_Prefix;

      Escape : constant String := Character'Val (27) & "[";
      Reset  : constant String := Escape & "0m";

      procedure Assert_Decoration
        (Decoration : Terminal_Styles.Text_Decoration;
         Code       : String)
      is
      begin
         Assert
           (Terminal_Styles.Decorate ("x", Decoration) = Escape & Code & "mx" & Reset,
            "decoration code " & Code);
      end Assert_Decoration;

      procedure Assert_Color
        (Color           : Terminal_Styles.Terminal_Color;
         Foreground_Code : String;
         Background_Code : String)
      is
      begin
         Assert
           (Terminal_Styles.Decorate ("x", Color)
            = Escape & Foreground_Code & ";49mx" & Reset,
            "foreground color code " & Foreground_Code);
         Assert
           (Terminal_Styles.Decorate ("x", Terminal_Styles.Color_Default, Color)
            = Escape & "39;" & Background_Code & "mx" & Reset,
            "background color code " & Background_Code);
      end Assert_Color;
   begin
      Assert (Terminal_Styles.Marker (Terminal_Styles.Role_Info) = "[*]", "info marker");
      Assert (Terminal_Styles.Marker (Terminal_Styles.Role_Success) = "[+]", "success marker");
      Assert (Terminal_Styles.Marker (Terminal_Styles.Role_Error) = "[!]", "error marker");
      Assert (Terminal_Styles.Marker (Terminal_Styles.Role_Warning) = "[-]", "warning marker");
      Assert (Terminal_Styles.Marker (Terminal_Styles.Role_Muted) = "[.]", "muted marker");
      Assert (Terminal_Styles.Marker (Terminal_Styles.Role_Header) = "[=]", "header marker");

      Save_Environment ("NO_COLOR", No_Color_Found, No_Color_Value);
      begin
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Auto);
         Ada.Environment_Variables.Set ("NO_COLOR", "1");
         Assert (not Terminal_Styles.Color_Enabled, "NO_COLOR disables ANSI color");
         Assert
           (Terminal_Styles.Decorate ("text", Terminal_Styles.Role_Error) = "text",
            "disabled color leaves text unchanged");
         Assert
           (Terminal_Styles.Line ("failed", Terminal_Styles.Role_Error) = "[!] failed",
            "disabled color keeps marker and text");
         Assert
           (Terminal_Styles.Decorate ("text", Terminal_Styles.Decoration_Bold) = "text",
            "disabled color leaves decorated text unchanged");
         Assert
           (Terminal_Styles.Decorate
              ("text", Terminal_Styles.Color_Red, Terminal_Styles.Color_Blue) = "text",
            "disabled color leaves colored text unchanged");
         Assert
           (Terminal_Styles.Decorate
              ("text", Terminal_Styles.Decoration_Underline,
               Terminal_Styles.Color_Red, Terminal_Styles.Color_Blue) = "text",
            "disabled color leaves combined styling unchanged");
         Sitefetch.Messages.Set_Locale ("en");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format (Progress_Fetching, "https://example.com"), "[*]"),
            "fetch progress uses info marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format (Progress_Written, "https://example.com"), "[+]"),
            "write progress uses success marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format (Progress_Skipped_External, "https://example.com"), "[-]"),
            "external progress uses warning marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format
                 (Progress_Skipped_Unsupported, "https://example.com"), "[.]"),
            "unsupported progress uses muted marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format
                 (Progress_Warning_Dangerous, "https://example.com"), "[-]"),
            "dangerous warning progress uses warning marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format
                 (Progress_Skipped_Dangerous, "https://example.com"), "[-]"),
            "dangerous skip progress uses warning marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format (Progress_Already_Visited, "https://example.com"), "[.]"),
            "visited progress uses muted marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format (Progress_Failed, "https://example.com"), "[!]"),
            "failed progress uses error marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format
                 (Progress_Cache_Revalidate, "https://example.com"), "[.]"),
            "cache revalidation progress uses muted marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format
                 (Progress_Cache_Reused, "https://example.com"), "[.]"),
            "cache reuse progress uses muted marker");
      Assert
        (Ada.Strings.Fixed.Index
           (Sitefetch.Progress_Format.Format
              (Progress_Cache_Rejected, "https://example.com"), "[.]") = 1,
         "cache rejection progress uses muted marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format
                 (Progress_Resume_Attempt, "https://example.com"), "[.]"),
            "resume progress uses muted marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format (Progress_Retry, "https://example.com"), "[-]"),
            "retry progress uses warning marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format
                 (Progress_Robots_Allowed, "https://example.com"), "[.]"),
            "robots allow progress uses muted marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format
                 (Progress_Robots_Disallowed, "https://example.com"), "[-]"),
            "robots disallow progress uses warning marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format
                 (Progress_Robots_Loaded, "https://example.com"), "[.]"),
            "robots loaded progress uses muted marker");
         Assert
           (Has_Prefix
              (Sitefetch.Progress_Format.Format
                 (Progress_Robots_Failed, "https://example.com"), "[-]"),
            "robots failed progress uses warning marker");
      exception
         when others =>
            Terminal_Styles.Set_Color_Policy (Saved_Policy);
            Restore_Environment ("NO_COLOR", No_Color_Found, No_Color_Value);
            raise;
      end;

      Restore_Environment ("NO_COLOR", No_Color_Found, No_Color_Value);

      Save_Environment ("NO_COLOR", No_Color_Found, No_Color_Value);
      begin
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Always);
         Ada.Environment_Variables.Clear ("NO_COLOR");
         Assert (Terminal_Styles.Color_Enabled, "Color_Always enables ANSI color");

         Assert_Decoration (Terminal_Styles.Decoration_Reset, "0");
         Assert_Decoration (Terminal_Styles.Decoration_Bold, "1");
         Assert_Decoration (Terminal_Styles.Decoration_Faint, "2");
         Assert_Decoration (Terminal_Styles.Decoration_Italic, "3");
         Assert_Decoration (Terminal_Styles.Decoration_Underline, "4");
         Assert_Decoration (Terminal_Styles.Decoration_Double_Underline, "21");
         Assert_Decoration (Terminal_Styles.Decoration_Slow_Blink, "5");
         Assert_Decoration (Terminal_Styles.Decoration_Rapid_Blink, "6");
         Assert_Decoration (Terminal_Styles.Decoration_Reverse, "7");
         Assert_Decoration (Terminal_Styles.Decoration_Conceal, "8");
         Assert_Decoration (Terminal_Styles.Decoration_Crossed_Out, "9");
         Assert_Decoration (Terminal_Styles.Decoration_Framed, "51");
         Assert_Decoration (Terminal_Styles.Decoration_Encircled, "52");
         Assert_Decoration (Terminal_Styles.Decoration_Overlined, "53");
         Assert_Decoration (Terminal_Styles.Decoration_Not_Bold_Or_Faint, "22");
         Assert_Decoration (Terminal_Styles.Decoration_Not_Italic, "23");
         Assert_Decoration (Terminal_Styles.Decoration_Not_Underlined, "24");
         Assert_Decoration (Terminal_Styles.Decoration_Not_Blinking, "25");
         Assert_Decoration (Terminal_Styles.Decoration_Not_Reversed, "27");
         Assert_Decoration (Terminal_Styles.Decoration_Reveal, "28");
         Assert_Decoration (Terminal_Styles.Decoration_Not_Crossed_Out, "29");
         Assert_Decoration (Terminal_Styles.Decoration_Not_Framed_Or_Encircled, "54");
         Assert_Decoration (Terminal_Styles.Decoration_Not_Overlined, "55");

         Assert_Color (Terminal_Styles.Color_Default, "39", "49");
         Assert_Color (Terminal_Styles.Color_Black, "30", "40");
         Assert_Color (Terminal_Styles.Color_Red, "31", "41");
         Assert_Color (Terminal_Styles.Color_Green, "32", "42");
         Assert_Color (Terminal_Styles.Color_Yellow, "33", "43");
         Assert_Color (Terminal_Styles.Color_Blue, "34", "44");
         Assert_Color (Terminal_Styles.Color_Magenta, "35", "45");
         Assert_Color (Terminal_Styles.Color_Cyan, "36", "46");
         Assert_Color (Terminal_Styles.Color_White, "37", "47");
         Assert_Color (Terminal_Styles.Color_Bright_Black, "90", "100");
         Assert_Color (Terminal_Styles.Color_Bright_Red, "91", "101");
         Assert_Color (Terminal_Styles.Color_Bright_Green, "92", "102");
         Assert_Color (Terminal_Styles.Color_Bright_Yellow, "93", "103");
         Assert_Color (Terminal_Styles.Color_Bright_Blue, "94", "104");
         Assert_Color (Terminal_Styles.Color_Bright_Magenta, "95", "105");
         Assert_Color (Terminal_Styles.Color_Bright_Cyan, "96", "106");
         Assert_Color (Terminal_Styles.Color_Bright_White, "97", "107");

         Assert
           (Terminal_Styles.Decorate
              ("x", Terminal_Styles.Decoration_Bold,
               Terminal_Styles.Color_Red, Terminal_Styles.Color_Blue)
            = Escape & "1;31;44mx" & Reset,
            "combined decoration and colors are emitted in one SGR sequence");
      exception
         when others =>
            Terminal_Styles.Set_Color_Policy (Saved_Policy);
            Restore_Environment ("NO_COLOR", No_Color_Found, No_Color_Value);
            raise;
      end;

      Restore_Environment ("NO_COLOR", No_Color_Found, No_Color_Value);
      Terminal_Styles.Set_Color_Policy (Saved_Policy);
   end Run_Test;

   function Run_Check_Sitefetch
     (Mode        : String;
      Target_Root : String) return Integer
   is
      Previous        : constant String := Ada.Directories.Current_Directory;
      Absolute_Target : constant String :=
        (if Target_Root'Length > 0 and then Target_Root (Target_Root'First) = '/'
         then Target_Root
         else Previous & "/" & Target_Root);
      Args            : GNAT.OS_Lib.Argument_List :=
        (1 => new String'("--quiet"),
         2 => new String'(Mode),
         3 => new String'(Absolute_Target));
   begin
      Ada.Directories.Set_Directory ("..");
      declare
         Status : constant Integer := GNAT.OS_Lib.Spawn ("./bin/check_sitefetch", Args);
      begin
         Ada.Directories.Set_Directory (Previous);
         return Status;
      end;
   exception
      when others =>
         if Ada.Directories.Current_Directory /= Previous then
            Ada.Directories.Set_Directory (Previous);
         end if;
         raise;
   end Run_Check_Sitefetch;

   procedure Stage_Source_Skeleton (Root : String) is
   begin
      Ada.Directories.Create_Path (Root & "/sitefetch/src");
      Ada.Directories.Create_Path (Root & "/sitefetchlib/src");
      Ada.Directories.Create_Path (Root & "/httpclient/src");

      Write_Test_File (Root & "/sitefetch/sitefetch.gpr", "project Sitefetch is end Sitefetch;" & ASCII.LF);
      Write_Test_File (Root & "/sitefetch/README.md", "sitefetch" & ASCII.LF);
      Write_Test_File (Root & "/sitefetch/LICENSE", "license" & ASCII.LF);

      Write_Test_File
        (Root & "/sitefetchlib/sitefetchlib.gpr",
         "project Sitefetchlib is end Sitefetchlib;" & ASCII.LF);
      Write_Test_File (Root & "/sitefetchlib/README.md", "sitefetchlib" & ASCII.LF);
      Write_Test_File (Root & "/sitefetchlib/LICENSE", "license" & ASCII.LF);

      Write_Test_File (Root & "/httpclient/httpclient.gpr", "project Httpclient is end Httpclient;" & ASCII.LF);
      Write_Test_File (Root & "/httpclient/README.md", "httpclient" & ASCII.LF);
      Write_Test_File (Root & "/httpclient/LICENSE", "license" & ASCII.LF);
   end Stage_Source_Skeleton;

   procedure Assert_Path_Exists (Path : String; Message : String) is
   begin
      Assert (Ada.Directories.Exists (Path), Message & ": " & Path);
   end Assert_Path_Exists;

   procedure Assert_Path_Absent (Path : String; Message : String) is
   begin
      Assert (not Ada.Directories.Exists (Path), Message & ": " & Path);
   end Assert_Path_Absent;

   procedure Assert_File_Contains
     (Path     : String;
      Fragment : String;
      Message  : String) is
   begin
      Assert (Contains_Fragment (Read_File (Path), Fragment), Message & ": " & Path);
   end Assert_File_Contains;

   procedure Assert_File_Excludes
     (Path     : String;
      Fragment : String;
      Message  : String) is
   begin
      Assert (not Contains_Fragment (Read_File (Path), Fragment), Message & ": " & Path);
   end Assert_File_Excludes;

   type Release_Crate_List is array (Positive range <>) of Unbounded_String;

   Release_Build_Crates : constant Release_Crate_List :=
     [To_Unbounded_String ("sitefetch"), To_Unbounded_String ("sitefetchlib"),
      To_Unbounded_String ("httpclient"), To_Unbounded_String ("zlib"),
      To_Unbounded_String ("regexp"), To_Unbounded_String ("i18n"),
      To_Unbounded_String ("terminal_styles"), To_Unbounded_String ("project_tools")];

   Release_Build_Overlay_Crates : constant Release_Crate_List :=
     [To_Unbounded_String ("sitefetch"), To_Unbounded_String ("sitefetchlib"),
      To_Unbounded_String ("httpclient")];

   overriding procedure Run_Test (Item : in out Release_Manifest_Tool_Test) is
      pragma Unreferenced (Item);
      Root : constant String := "/tmp/sitefetch_release_manifest_tool";
   begin
      Delete_Tree_If_Present (Root);

      Assert
        (Run_Check_Sitefetch ("--prepare-release-manifests", Root) = 0,
         "prepare-release-manifests should create a valid staged manifest set");
      Assert
        (Run_Check_Sitefetch ("--validate-release-manifests", Root) = 0,
         "validate-release-manifests should accept freshly prepared manifests");
      Stage_Source_Skeleton (Root);
      Assert
        (Run_Check_Sitefetch ("--validate-release-source", Root) = 0,
         "validate-release-source should accept staged source skeletons");

      Delete_Tree_If_Present (Root);
      Assert
        (Run_Check_Sitefetch ("--prepare-release-source", Root) = 0,
         "prepare-release-source should stage and validate release source trees");
      Assert
        (Run_Check_Sitefetch ("--validate-release-source", Root) = 0,
         "validate-release-source should accept prepared release source trees");

      Delete_Tree_If_Present (Root);
      Assert
        (Run_Check_Sitefetch ("--prepare-release-build", Root) = 0,
         "prepare-release-build should stage release source plus build-only dependency overlays");
      Assert
        (Run_Check_Sitefetch ("--validate-release-build-workspace", Root) = 0,
         "validate-release-build-workspace should accept prepared release build workspaces");

      for Crate_Name of Release_Build_Crates loop
         declare
            Crate : constant String := To_String (Crate_Name);
         begin
            Assert_Path_Exists (Root & "/" & Crate, "release build workspace should stage crate");
            Assert_Path_Absent (Root & "/" & Crate & "/alire", "release build workspace should skip alire state");
            Assert_Path_Absent (Root & "/" & Crate & "/bin", "release build workspace should skip binaries");
            Assert_Path_Absent (Root & "/" & Crate & "/obj", "release build workspace should skip object files");
            Assert_Path_Absent (Root & "/" & Crate & "/config", "release build workspace should skip config output");
            Assert_Path_Absent (Root & "/" & Crate & "/lib", "release build workspace should skip library output");
         end;
      end loop;

      for Crate_Name of Release_Build_Overlay_Crates loop
         declare
            Crate : constant String := To_String (Crate_Name);
         begin
            Assert_Path_Exists (Root & "/" & Crate & "/alire.toml", "publish manifest should be staged");
            Assert_Path_Exists (Root & "/" & Crate & "/alire.build.toml", "build overlay should be staged");
            Assert_File_Excludes
              (Root & "/" & Crate & "/alire.toml",
               "[[pins]]",
               "publish manifest should stay pin-free");
            Assert_File_Excludes
              (Root & "/" & Crate & "/alire.toml",
               "path =",
               "publish manifest should stay free of local path pins");
            Assert_File_Contains
              (Root & "/" & Crate & "/alire.build.toml",
               "[[pins]]",
               "build overlay should contain local pins");
            Assert_File_Contains
              (Root & "/" & Crate & "/alire.build.toml",
               "path =",
               "build overlay should contain local path pins");
         end;
      end loop;

      Assert_File_Contains
        (Root & "/sitefetch/alire.build.toml",
         "sitefetchlib = { path = ""../sitefetchlib"" }",
         "sitefetch build overlay should pin sitefetchlib");
      Assert_File_Contains
        (Root & "/sitefetch/alire.build.toml",
         "i18n = { path = ""../i18n"" }",
         "sitefetch build overlay should pin i18n");
      Assert_File_Contains
        (Root & "/sitefetch/alire.build.toml",
         "terminal_styles = { path = ""../terminal_styles"" }",
         "sitefetch build overlay should pin terminal");
      Assert_File_Contains
        (Root & "/sitefetch/alire.build.toml",
         "project_tools = { path = ""../project_tools"" }",
         "sitefetch build overlay should pin project_tools");
      Assert_File_Contains
        (Root & "/sitefetchlib/alire.build.toml",
         "httpclient = { path = ""../httpclient"" }",
         "sitefetchlib build overlay should pin httpclient");
      Assert_File_Contains
        (Root & "/sitefetchlib/alire.build.toml",
         "regexp = { path = ""../regexp"" }",
         "sitefetchlib build overlay should pin regexp");
      Assert_File_Contains
        (Root & "/sitefetchlib/alire.build.toml",
         "zlib = { path = ""../zlib"" }",
         "sitefetchlib build overlay should pin zlib");
      Assert_File_Contains
        (Root & "/httpclient/alire.build.toml",
         "zlib = { path = ""../zlib"" }",
         "httpclient build overlay should pin zlib");

      Write_Test_File
        (Root & "/sitefetch/alire.build.toml",
         "name = ""sitefetch""" & ASCII.LF
         & "[[pins]]" & ASCII.LF
         & "sitefetchlib = { path = ""../sitefetchlib"" }" & ASCII.LF);
      Assert
        (Run_Check_Sitefetch ("--validate-release-build-workspace", Root) /= 0,
         "validate-release-build-workspace should reject overlays not derived from release templates");

      Write_Test_File
        (Root & "/sitefetch/alire.toml",
         "name = ""sitefetch""" & ASCII.LF
         & "[[depends-on]]" & ASCII.LF
         & "sitefetchlib = ""*""" & ASCII.LF
         & "[[depends-on]]" & ASCII.LF
         & "i18n = ""*""" & ASCII.LF
         & "[[depends-on]]" & ASCII.LF
         & "terminal_styles = ""*""" & ASCII.LF
         & "[[depends-on]]" & ASCII.LF
         & "project_tools = ""*""" & ASCII.LF
         & "[[pins]]" & ASCII.LF
         & "sitefetchlib = { path = ""../sitefetchlib"" }" & ASCII.LF);
      Assert
        (Run_Check_Sitefetch ("--validate-release-manifests", Root) /= 0,
         "validate-release-manifests should reject staged local pins");

      Assert
        (Run_Check_Sitefetch ("--prepare-release-manifests", Root) = 0,
         "prepare-release-manifests should restore a clean staged manifest set");
      Write_Test_File
        (Root & "/sitefetch/alire.toml",
         "name = ""sitefetch""" & ASCII.LF
         & "[[depends-on]]" & ASCII.LF
         & "i18n = ""*""" & ASCII.LF
         & "[[depends-on]]" & ASCII.LF
         & "terminal_styles = ""*""" & ASCII.LF
         & "[[depends-on]]" & ASCII.LF
         & "project_tools = ""*""" & ASCII.LF);
      Assert
        (Run_Check_Sitefetch ("--validate-release-manifests", Root) /= 0,
         "validate-release-manifests should reject missing required dependencies");

      Assert
        (Run_Check_Sitefetch ("--prepare-release-manifests", Root) = 0,
         "prepare-release-manifests should restore staged manifests for source validation");
      Stage_Source_Skeleton (Root);
      Ada.Directories.Delete_File (Root & "/sitefetch/LICENSE");
      Assert
        (Run_Check_Sitefetch ("--validate-release-source", Root) /= 0,
         "validate-release-source should reject missing source release files");

      Delete_Tree_If_Present (Root);
   exception
      when others =>
         Delete_Tree_If_Present (Root);
         raise;
   end Run_Test;

   type String_List is array (Positive range <>) of Unbounded_String;

   Expected_Locales : constant String_List :=
     [To_Unbounded_String ("en"), To_Unbounded_String ("de"), To_Unbounded_String ("fr"),
      To_Unbounded_String ("es"), To_Unbounded_String ("pt"), To_Unbounded_String ("it"),
      To_Unbounded_String ("nl"), To_Unbounded_String ("da"), To_Unbounded_String ("sv"),
      To_Unbounded_String ("nb"), To_Unbounded_String ("pl"), To_Unbounded_String ("cs"),
      To_Unbounded_String ("sk"), To_Unbounded_String ("hu"), To_Unbounded_String ("ro"),
      To_Unbounded_String ("sl"), To_Unbounded_String ("hr"), To_Unbounded_String ("bg"),
      To_Unbounded_String ("uk"), To_Unbounded_String ("ru"), To_Unbounded_String ("lt"),
      To_Unbounded_String ("lv"), To_Unbounded_String ("et")];

   Expected_Message_Keys : constant String_List :=
     [To_Unbounded_String ("usage.line1"), To_Unbounded_String ("usage.line2"),
      To_Unbounded_String ("usage.description"), To_Unbounded_String ("usage.scheme"),
      To_Unbounded_String ("usage.quiet"), To_Unbounded_String ("usage.verbose"),
      To_Unbounded_String ("usage.locale"),
      To_Unbounded_String ("error.prefix"), To_Unbounded_String ("error.target_empty"),
      To_Unbounded_String ("error.target_not_directory"), To_Unbounded_String ("error.target_inspect"),
      To_Unbounded_String ("error.locale_missing"), To_Unbounded_String ("error.locale_empty"),
      To_Unbounded_String ("error.unknown_option"), To_Unbounded_String ("error.too_many_arguments"),
      To_Unbounded_String ("error.missing_url"), To_Unbounded_String ("error.fetch_exception"),
      To_Unbounded_String ("version"), To_Unbounded_String ("start.fetching"),
      To_Unbounded_String ("start.target"), To_Unbounded_String ("status.completed"),
      To_Unbounded_String ("status.failed"), To_Unbounded_String ("status.failed_reason"),
      To_Unbounded_String ("summary.attempted"),
      To_Unbounded_String ("summary.written"), To_Unbounded_String ("summary.external"),
      To_Unbounded_String ("summary.ignored"), To_Unbounded_String ("summary.failed"),
      To_Unbounded_String ("summary.elapsed"), To_Unbounded_String ("summary.failed_url"),
      To_Unbounded_String ("summary.failed_reason"), To_Unbounded_String ("progress.fetch"),
      To_Unbounded_String ("progress.write"),
      To_Unbounded_String ("progress.external"), To_Unbounded_String ("progress.ignore"),
      To_Unbounded_String ("progress.danger"), To_Unbounded_String ("progress.skip_danger"),
      To_Unbounded_String ("progress.visited"), To_Unbounded_String ("progress.fail"),
      To_Unbounded_String ("progress.cache_revalidate"),
      To_Unbounded_String ("progress.cache_reused"), To_Unbounded_String ("progress.cache_rejected"),
      To_Unbounded_String ("progress.resume"),
      To_Unbounded_String ("progress.retry"), To_Unbounded_String ("progress.robots_allow"),
      To_Unbounded_String ("progress.robots_disallow"),
      To_Unbounded_String ("progress.robots_loaded"),
      To_Unbounded_String ("progress.robots_failed")];

   function Starts_With (Item : String; Prefix : String) return Boolean is
   begin
      return Item'Length >= Prefix'Length
        and then Item (Item'First .. Item'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Catalog_Path return String is
   begin
      if Ada.Directories.Exists ("share/sitefetch/messages.catalog") then
         return "share/sitefetch/messages.catalog";
      else
         return "../share/sitefetch/messages.catalog";
      end if;
   end Catalog_Path;

   function Catalog_Has (Locale : String; Key : String) return Boolean is
      File   : Ada.Text_IO.File_Type;
      Buffer : String (1 .. 1_024);
      Last   : Natural;
      Prefix : constant String := Locale & "." & Key & " =";
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Catalog_Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Buffer, Last);
         if Last >= Prefix'Length and then Starts_With (Buffer (1 .. Last), Prefix) then
            Ada.Text_IO.Close (File);
            return True;
         end if;
      end loop;
      Ada.Text_IO.Close (File);
      return False;
   end Catalog_Has;


   function Contains (Item : String; Fragment : String) return Boolean is
   begin
      if Fragment'Length = 0 then
         return True;
      elsif Item'Length < Fragment'Length then
         return False;
      end if;

      for Index_Value in Item'First .. Item'Last - Fragment'Length + 1 loop
         if Item (Index_Value .. Index_Value + Fragment'Length - 1) = Fragment then
            return True;
         end if;
      end loop;

      return False;
   end Contains;

   function Catalog_Line_Contains
     (Locale   : String;
      Key      : String;
      Fragment : String) return Boolean
   is
      File   : Ada.Text_IO.File_Type;
      Buffer : String (1 .. 1_024);
      Last   : Natural;
      Prefix : constant String := Locale & "." & Key & " =";
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Catalog_Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Buffer, Last);
         if Last >= Prefix'Length and then Starts_With (Buffer (1 .. Last), Prefix) then
            declare
               Found : constant Boolean := Contains (Buffer (1 .. Last), Fragment);
            begin
               Ada.Text_IO.Close (File);
               return Found;
            end;
         end if;
      end loop;
      Ada.Text_IO.Close (File);
      return False;
   end Catalog_Line_Contains;

   function Catalog_Key_Count (Locale : String) return Natural is
      File   : Ada.Text_IO.File_Type;
      Buffer : String (1 .. 1_024);
      Last   : Natural;
      Prefix : constant String := Locale & ".";
      Count  : Natural := 0;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Catalog_Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Buffer, Last);
         if Last >= Prefix'Length and then Starts_With (Buffer (1 .. Last), Prefix) then
            Count := Count + 1;
         end if;
      end loop;
      Ada.Text_IO.Close (File);
      return Count;
   end Catalog_Key_Count;

   overriding procedure Run_Test (Item : in out Catalog_Completeness_Test) is
      pragma Unreferenced (Item);
   begin
      for Locale_Item of Expected_Locales loop
         declare
            Locale : constant String := To_String (Locale_Item);
         begin
            Assert
              (Catalog_Key_Count (Locale) = Expected_Message_Keys'Length,
               "catalog key count matches English for " & Locale);

            for Key_Item of Expected_Message_Keys loop
               Assert
                 (Catalog_Has (Locale, To_String (Key_Item)),
                  "catalog contains " & Locale & "." & To_String (Key_Item));
            end loop;

            Assert (Catalog_Line_Contains (Locale, "error.prefix", "{message}"), "message placeholder");
            Assert (Catalog_Line_Contains (Locale, "version", "{version}"), "version placeholder");
            Assert (Catalog_Line_Contains (Locale, "error.unknown_option", "{option}"), "option placeholder");
            Assert (Catalog_Line_Contains (Locale, "error.target_not_directory", "{target}"), "target placeholder");
            Assert (Catalog_Line_Contains (Locale, "error.target_inspect", "{target}"), "inspect target placeholder");
            Assert (Catalog_Line_Contains (Locale, "start.target", "{target}"), "start target placeholder");
            Assert (Catalog_Line_Contains (Locale, "start.fetching", "{url}"), "start URL placeholder");
            Assert (Catalog_Line_Contains (Locale, "status.failed_reason", "{reason}"), "failed status reason");
            Assert (Catalog_Line_Contains (Locale, "summary.failed_url", "{url}"), "failed URL placeholder");
            Assert (Catalog_Line_Contains (Locale, "summary.failed_reason", "{reason}"), "failed reason");
            Assert (Catalog_Line_Contains (Locale, "summary.attempted", "{count}"), "attempted count");
            Assert (Catalog_Line_Contains (Locale, "summary.written", "{count}"), "written count");
            Assert (Catalog_Line_Contains (Locale, "summary.external", "{count}"), "external count");
            Assert (Catalog_Line_Contains (Locale, "summary.ignored", "{count}"), "ignored count");
            Assert (Catalog_Line_Contains (Locale, "summary.failed", "{count}"), "failed count");
            Assert (Catalog_Line_Contains (Locale, "summary.elapsed", "{duration}"), "elapsed duration");
            Assert (Catalog_Line_Contains (Locale, "progress.fetch", "{url}"), "progress fetch URL");
            Assert (Catalog_Line_Contains (Locale, "progress.write", "{url}"), "progress write URL");
            Assert (Catalog_Line_Contains (Locale, "progress.external", "{url}"), "progress external URL");
            Assert (Catalog_Line_Contains (Locale, "progress.ignore", "{url}"), "progress ignore URL");
            Assert (Catalog_Line_Contains (Locale, "progress.danger", "{url}"), "progress danger URL");
            Assert
              (Catalog_Line_Contains (Locale, "progress.skip_danger", "{url}"),
               "progress skip danger URL");
            Assert (Catalog_Line_Contains (Locale, "progress.visited", "{url}"), "progress visited URL");
            Assert (Catalog_Line_Contains (Locale, "progress.fail", "{url}"), "progress fail URL");
            Assert
              (Catalog_Line_Contains (Locale, "progress.cache_revalidate", "{url}"),
               "progress cache revalidate URL");
            Assert
              (Catalog_Line_Contains (Locale, "progress.cache_reused", "{url}"),
               "progress cache reused URL");
            Assert (Catalog_Line_Contains (Locale, "progress.resume", "{url}"), "progress resume URL");
            Assert (Catalog_Line_Contains (Locale, "progress.retry", "{url}"), "progress retry URL");
            Assert
              (Catalog_Line_Contains (Locale, "progress.robots_allow", "{url}"),
               "progress robots allow URL");
            Assert
              (Catalog_Line_Contains (Locale, "progress.robots_disallow", "{url}"),
               "progress robots disallow URL");
            Assert
              (Catalog_Line_Contains (Locale, "progress.robots_loaded", "{url}"),
               "progress robots loaded URL");
            Assert
              (Catalog_Line_Contains (Locale, "progress.robots_failed", "{url}"),
               "progress robots failed URL");
         end;
      end loop;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (new CLI_Parse_Test);
      Result.Add_Test (new App_Run_Test);
      Result.Add_Test (new Message_Locale_Test);
      Result.Add_Test (new Terminal_Format_Test);
      Result.Add_Test (new Release_Manifest_Tool_Test);
      Result.Add_Test (new Catalog_Completeness_Test);
      return Result;
   end Suite;
end Sitefetch.Tests;
