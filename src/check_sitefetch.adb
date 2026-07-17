with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;

with Project_Tools.Alire_Manifests;
with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Release_Checks;
with Project_Tools.Tree_Checks;

procedure Check_Sitefetch is
   use Ada.Text_IO;
   use GNAT.OS_Lib;
   use type Ada.Directories.File_Kind;

   Root_Dir : constant String := Ada.Directories.Current_Directory;
   Sitefetchlib_Dir : constant String := Root_Dir & "/../sitefetchlib";
   Httpclient_Dir   : constant String := Root_Dir & "/../HttpClient";
   I18n_Dir         : constant String := Root_Dir & "/../i18n";
   Regexp_Dir       : constant String := Root_Dir & "/../regexp";
   Terminal_Styles_Dir : constant String := Root_Dir & "/../terminal_styles";
   Project_Tools_Dir : constant String := Root_Dir & "/../project_tools";
   Zlib_Dir         : constant String := Root_Dir & "/../zlib";

   procedure Run
     (Label   : String;
      Dir     : String;
      Program : String;
      Args    : Argument_List) is
   begin
      Project_Tools.Release_Checks.Run
        (Label   => Label,
         Dir     => Dir,
         Program => Program,
         Args    => Args);
   end Run;

   function Quiet_Mode return Boolean;

   function Alr_Path return String is
   begin
      Project_Tools.Processes.Require_Command
        ("alr",
         "alr executable not found on PATH",
         Quiet_Mode);
      return Project_Tools.Processes.Locate_Command ("alr");
   end Alr_Path;

   Build_Args : constant Argument_List := (1 => new String'("build"));
   Gnatprove_Check_Args : constant Argument_List :=
     (1 => new String'("exec"),
      2 => new String'("--"),
      3 => new String'("gnatprove"),
      4 => new String'("-P"),
      5 => new String'("sitefetch.gpr"),
      6 => new String'("--level=0"),
      7 => new String'("--mode=check"));
   Exec_CLI_Tests_Args : constant Argument_List :=
     (1 => new String'("exec"), 2 => new String'("--"), 3 => new String'("./bin/tests"));
   GNAT_Version_Args : constant Argument_List :=
     (1 => new String'("exec"),
      2 => new String'("--"),
      3 => new String'("gnatls"),
      4 => new String'("--version"));

   function Quiet_Mode return Boolean is
   begin
      return Ada.Command_Line.Argument_Count >= 1
        and then Ada.Command_Line.Argument (1) = "--quiet";
   end Quiet_Mode;

   function Mode_Argument_Index return Positive is
   begin
      if Quiet_Mode then
         return 2;
      else
         return 1;
      end if;
   end Mode_Argument_Index;

   function Target_Argument_Index return Positive is
   begin
      if Quiet_Mode then
         return 3;
      else
         return 2;
      end if;
   end Target_Argument_Index;

   function Is_Command_Mode (Argument : String) return Boolean is
   begin
      return Argument = "--prepare-release-manifests"
        or else Argument = "--prepare-release-source"
        or else Argument = "--prepare-release-build"
        or else Argument = "--validate-release-manifests"
        or else Argument = "--validate-release-build-workspace"
        or else Argument = "--validate-release-source"
        or else Argument = "--validate-release-build";
   end Is_Command_Mode;

   package File_Checks renames Project_Tools.Files;
   package Manifest_Checks renames Project_Tools.Alire_Manifests;

   Sitefetch_Release_Template    : constant String := Root_Dir & "/sitefetch.alire.release.toml";
   Sitefetchlib_Release_Template : constant String := Sitefetchlib_Dir & "/sitefetchlib.alire.release.toml";
   Httpclient_Release_Template   : constant String := Httpclient_Dir & "/httpclient.alire.release.toml";

   procedure Audit_Development_Workspace_Pins is
   begin
      File_Checks.Require_Contains
        (Root_Dir & "/alire.toml",
         "gnat_native = ""=15.2.1""",
         "sitefetch development manifest must pin Alire GNAT 15", Quiet_Mode);
      File_Checks.Require_Contains
        (Root_Dir & "/tests/alire.toml",
         "gnat_native = ""=15.2.1""",
         "sitefetch tests manifest must pin Alire GNAT 15", Quiet_Mode);
      Manifest_Checks.Require_Workspace_Pin (Root_Dir & "/alire.toml", "sitefetchlib", "../sitefetchlib", Quiet_Mode);
      Manifest_Checks.Require_Workspace_Pin (Root_Dir & "/alire.toml", "i18n", "../i18n", Quiet_Mode);
      Manifest_Checks.Require_Workspace_Pin
        (Root_Dir & "/alire.toml", "terminal_styles", "../terminal_styles", Quiet_Mode);
      Manifest_Checks.Require_Workspace_Pin (Root_Dir & "/alire.toml", "project_tools", "../project_tools", Quiet_Mode);

      Manifest_Checks.Require_Workspace_Pin
        (Sitefetchlib_Dir & "/alire.toml", "httpclient", "../HttpClient", Quiet_Mode);
      Manifest_Checks.Require_Workspace_Pin (Sitefetchlib_Dir & "/alire.toml", "regexp", "../regexp", Quiet_Mode);
      Manifest_Checks.Require_Workspace_Pin (Sitefetchlib_Dir & "/alire.toml", "zlib", "../zlib", Quiet_Mode);

      Manifest_Checks.Require_Workspace_Pin (Httpclient_Dir & "/alire.toml", "zlib", "../zlib", Quiet_Mode);

      Manifest_Checks.Require_Pin_Free_Crate_Manifest
        (Project_Tools_Dir & "/alire.toml", "project_tools", Quiet_Mode);
      Manifest_Checks.Require_Pin_Free_Crate_Manifest
        (Zlib_Dir & "/alire.toml", "zlib", Quiet_Mode);
   end Audit_Development_Workspace_Pins;

   procedure Audit_Release_Templates is
   begin
      File_Checks.Require_Contains
        (Sitefetch_Release_Template,
         "gnat_native = ""=15.2.1""",
         "sitefetch release manifest must pin Alire GNAT 15", Quiet_Mode);
      Manifest_Checks.Require_No_Local_Pins (Sitefetch_Release_Template, Quiet_Mode);
      Manifest_Checks.Require_Release_Dependencies
        (Sitefetch_Release_Template,
         [Ada.Strings.Unbounded.To_Unbounded_String ("sitefetchlib"),
          Ada.Strings.Unbounded.To_Unbounded_String ("i18n"),
          Ada.Strings.Unbounded.To_Unbounded_String ("terminal_styles"),
          Ada.Strings.Unbounded.To_Unbounded_String ("project_tools")],
         Quiet_Mode);

      Manifest_Checks.Require_No_Local_Pins (Sitefetchlib_Release_Template, Quiet_Mode);
      Manifest_Checks.Require_Release_Dependencies
        (Sitefetchlib_Release_Template,
         [Ada.Strings.Unbounded.To_Unbounded_String ("httpclient"),
          Ada.Strings.Unbounded.To_Unbounded_String ("regexp"),
          Ada.Strings.Unbounded.To_Unbounded_String ("zlib")],
         Quiet_Mode);

      Manifest_Checks.Require_No_Local_Pins (Httpclient_Release_Template, Quiet_Mode);
      Manifest_Checks.Require_Release_Dependency (Httpclient_Release_Template, "zlib", Quiet_Mode);

      File_Checks.Require_Contains
        (Root_Dir & "/README.md",
         "Before publishing or tagging a release archive",
         "sitefetch README must document release handling for local pins", Quiet_Mode);
      File_Checks.Require_Contains
        (Sitefetchlib_Dir & "/README.md",
         "Before publishing or tagging a release archive",
         "sitefetchlib README must document release handling for local pins", Quiet_Mode);
      File_Checks.Require_Contains
        (Httpclient_Dir & "/README.md",
         "temporary workspace pin",
         "HttpClient README must document the zlib workspace pin release blocker", Quiet_Mode);
      File_Checks.Require_Contains
        (Root_Dir & "/README.md",
         "docs/SPARK.md",
         "sitefetch README must link SPARK coverage documentation", Quiet_Mode);
      File_Checks.Require_Contains
        (Root_Dir & "/README.md",
         "gnat_native = ""=15.2.1""",
         "sitefetch README must document the pinned Alire GNAT 15 toolchain", Quiet_Mode);
      File_Checks.Require_Contains
        (Root_Dir & "/AGENTS.md",
         "gnat_native = ""=15.2.1""",
         "sitefetch agent instructions must document the pinned Alire GNAT 15 toolchain", Quiet_Mode);
      File_Checks.Require_Contains
        (Root_Dir & "/docs/SPARK.md",
         "alr exec -- gnatprove -P sitefetch.gpr --level=0 --mode=check",
         "sitefetch SPARK documentation must include the release GNATprove command", Quiet_Mode);
      File_Checks.Require_Contains
        (Root_Dir & "/docs/SPARK.md",
         "Sitefetch.App_Format",
         "sitefetch SPARK documentation must describe extracted app formatting coverage", Quiet_Mode);
   end Audit_Release_Templates;

   procedure Audit_Release_Staging_Inputs is
   begin
      Audit_Development_Workspace_Pins;
      Audit_Release_Templates;
   end Audit_Release_Staging_Inputs;

   procedure Prepare_Release_Manifests (Target_Root : String) is
      Sitefetch_Target    : constant String := Target_Root & "/sitefetch";
      Sitefetchlib_Target : constant String := Target_Root & "/sitefetchlib";
      Httpclient_Target   : constant String := Target_Root & "/HttpClient";
   begin
      Audit_Release_Staging_Inputs;

      Ada.Directories.Create_Path (Sitefetch_Target);
      Ada.Directories.Create_Path (Sitefetchlib_Target);
      Ada.Directories.Create_Path (Httpclient_Target);

      Manifest_Checks.Copy_Release_Manifest
        (Sitefetch_Release_Template,
         Sitefetch_Target & "/alire.toml",
         Quiet_Mode);
      Manifest_Checks.Copy_Release_Manifest
        (Sitefetchlib_Release_Template,
         Sitefetchlib_Target & "/alire.toml",
         Quiet_Mode);
      Manifest_Checks.Copy_Release_Manifest
        (Httpclient_Release_Template,
         Httpclient_Target & "/alire.toml",
         Quiet_Mode);

      if not Quiet_Mode then
         Put_Line ("prepared release manifests under " & Target_Root);
      end if;
   exception
      when Program_Error =>
         raise;
      when others =>
         if not Quiet_Mode then
            Put_Line (Standard_Error, "failed to prepare release manifests under " & Target_Root);
         end if;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
   end Prepare_Release_Manifests;

   Release_Skip_Entries : constant File_Checks.Name_List :=
     [Ada.Strings.Unbounded.To_Unbounded_String ("."),
      Ada.Strings.Unbounded.To_Unbounded_String (".."),
      Ada.Strings.Unbounded.To_Unbounded_String (".git"),
      Ada.Strings.Unbounded.To_Unbounded_String (".agents"),
      Ada.Strings.Unbounded.To_Unbounded_String (".codex"),
      Ada.Strings.Unbounded.To_Unbounded_String ("alire"),
      Ada.Strings.Unbounded.To_Unbounded_String ("bin"),
      Ada.Strings.Unbounded.To_Unbounded_String ("obj"),
      Ada.Strings.Unbounded.To_Unbounded_String ("lib"),
      Ada.Strings.Unbounded.To_Unbounded_String ("config")];

   Release_Skip_Files : constant File_Checks.Name_List :=
     [Ada.Strings.Unbounded.To_Unbounded_String ("alire.toml"),
      Ada.Strings.Unbounded.To_Unbounded_String ("alire.lock")];

   procedure Validate_Staged_Release_Source (Target_Root : String);
   procedure Validate_Staged_Release_Build_Workspace (Target_Root : String);

   procedure Prepare_Release_Source (Target_Root : String) is
      Sitefetch_Target    : constant String := Target_Root & "/sitefetch";
      Sitefetchlib_Target : constant String := Target_Root & "/sitefetchlib";
      Httpclient_Target   : constant String := Target_Root & "/HttpClient";
   begin
      Audit_Release_Staging_Inputs;

      File_Checks.Copy_Release_Source_Tree
        (Root_Dir, Sitefetch_Target, Release_Skip_Entries, Release_Skip_Files, Quiet_Mode);
      File_Checks.Copy_Release_Source_Tree
        (Sitefetchlib_Dir, Sitefetchlib_Target, Release_Skip_Entries, Release_Skip_Files, Quiet_Mode);
      File_Checks.Copy_Release_Source_Tree
        (Httpclient_Dir, Httpclient_Target, Release_Skip_Entries, Release_Skip_Files, Quiet_Mode);

      Manifest_Checks.Copy_Release_Manifest
        (Sitefetch_Release_Template,
         Sitefetch_Target & "/alire.toml",
         Quiet_Mode);
      Manifest_Checks.Copy_Release_Manifest
        (Sitefetchlib_Release_Template,
         Sitefetchlib_Target & "/alire.toml",
         Quiet_Mode);
      Manifest_Checks.Copy_Release_Manifest
        (Httpclient_Release_Template,
         Httpclient_Target & "/alire.toml",
         Quiet_Mode);

      Validate_Staged_Release_Source (Target_Root);

      if not Quiet_Mode then
         Put_Line ("prepared release source under " & Target_Root);
      end if;
   end Prepare_Release_Source;

   procedure Write_Build_Manifest_Overlays (Target_Root : String) is
   begin
      Manifest_Checks.Write_Build_Manifest_Overlay
        (Httpclient_Release_Template,
         Target_Root & "/HttpClient/alire.build.toml",
         "[[pins]]" & ASCII.LF
         & "zlib = { path = ""../zlib"" }" & ASCII.LF,
         Quiet_Mode);

      Manifest_Checks.Write_Build_Manifest_Overlay
        (Sitefetchlib_Release_Template,
         Target_Root & "/sitefetchlib/alire.build.toml",
         "[[pins]]" & ASCII.LF
         & "httpclient = { path = ""../HttpClient"" }" & ASCII.LF
         & "[[pins]]" & ASCII.LF
         & "regexp = { path = ""../regexp"" }" & ASCII.LF
         & "[[pins]]" & ASCII.LF
         & "zlib = { path = ""../zlib"" }" & ASCII.LF,
         Quiet_Mode);

      Manifest_Checks.Write_Build_Manifest_Overlay
        (Sitefetch_Release_Template,
         Target_Root & "/sitefetch/alire.build.toml",
         "[[pins]]" & ASCII.LF
         & "sitefetchlib = { path = ""../sitefetchlib"" }" & ASCII.LF
         & "[[pins]]" & ASCII.LF
         & "i18n = { path = ""../i18n"" }" & ASCII.LF
         & "[[pins]]" & ASCII.LF
         & "terminal_styles = { path = ""../terminal_styles"" }" & ASCII.LF
         & "[[pins]]" & ASCII.LF
         & "project_tools = { path = ""../project_tools"" }" & ASCII.LF,
         Quiet_Mode);
   end Write_Build_Manifest_Overlays;

   procedure Prepare_Release_Build (Target_Root : String) is
   begin
      Prepare_Release_Source (Target_Root);

      File_Checks.Copy_Release_Source_Tree
        (I18n_Dir, Target_Root & "/i18n", Release_Skip_Entries, Release_Skip_Files, Quiet_Mode);
      File_Checks.Copy_Release_Source_Tree
        (Regexp_Dir, Target_Root & "/regexp", Release_Skip_Entries, Release_Skip_Files, Quiet_Mode);
      File_Checks.Copy_Release_Source_Tree
        (Terminal_Styles_Dir, Target_Root & "/terminal_styles", Release_Skip_Entries, Release_Skip_Files, Quiet_Mode);
      File_Checks.Copy_Release_Source_Tree
        (Project_Tools_Dir, Target_Root & "/project_tools", Release_Skip_Entries, Release_Skip_Files, Quiet_Mode);
      File_Checks.Copy_Release_Source_Tree
        (Zlib_Dir, Target_Root & "/zlib", Release_Skip_Entries, Release_Skip_Files, Quiet_Mode);
      Manifest_Checks.Copy_Dependency_Manifest (I18n_Dir, Target_Root & "/i18n", Quiet_Mode);
      Manifest_Checks.Copy_Dependency_Manifest (Regexp_Dir, Target_Root & "/regexp", Quiet_Mode);
      Manifest_Checks.Copy_Dependency_Manifest (Terminal_Styles_Dir, Target_Root & "/terminal_styles", Quiet_Mode);
      Manifest_Checks.Copy_Dependency_Manifest (Project_Tools_Dir, Target_Root & "/project_tools", Quiet_Mode);
      Manifest_Checks.Copy_Dependency_Manifest (Zlib_Dir, Target_Root & "/zlib", Quiet_Mode);

      Write_Build_Manifest_Overlays (Target_Root);
      Validate_Staged_Release_Build_Workspace (Target_Root);

      if not Quiet_Mode then
         Put_Line ("prepared release build workspace under " & Target_Root);
      end if;
   end Prepare_Release_Build;

   procedure Validate_Staged_Release_Manifests (Target_Root : String) is
      Sitefetch_Manifest    : constant String := Target_Root & "/sitefetch/alire.toml";
      Sitefetchlib_Manifest : constant String := Target_Root & "/sitefetchlib/alire.toml";
      Httpclient_Manifest   : constant String := Target_Root & "/HttpClient/alire.toml";
   begin
      Manifest_Checks.Require_Pin_Free_Crate_Manifest
        (Sitefetch_Manifest, "sitefetch", Quiet_Mode);
      Manifest_Checks.Require_Release_Dependencies
        (Sitefetch_Manifest,
         [Ada.Strings.Unbounded.To_Unbounded_String ("sitefetchlib"),
          Ada.Strings.Unbounded.To_Unbounded_String ("i18n"),
          Ada.Strings.Unbounded.To_Unbounded_String ("terminal_styles"),
          Ada.Strings.Unbounded.To_Unbounded_String ("project_tools")],
         Quiet_Mode);

      Manifest_Checks.Require_Pin_Free_Crate_Manifest
        (Sitefetchlib_Manifest, "sitefetchlib", Quiet_Mode);
      Manifest_Checks.Require_Release_Dependencies
        (Sitefetchlib_Manifest,
         [Ada.Strings.Unbounded.To_Unbounded_String ("httpclient"),
          Ada.Strings.Unbounded.To_Unbounded_String ("regexp"),
          Ada.Strings.Unbounded.To_Unbounded_String ("zlib")],
         Quiet_Mode);

      Manifest_Checks.Require_Pin_Free_Crate_Manifest
        (Httpclient_Manifest, "httpclient", Quiet_Mode);
      Manifest_Checks.Require_Release_Dependency (Httpclient_Manifest, "zlib", Quiet_Mode);

      if not Quiet_Mode then
         Put_Line ("validated staged release manifests under " & Target_Root);
      end if;
   end Validate_Staged_Release_Manifests;

   procedure Validate_Staged_Release_Source (Target_Root : String) is
      Sitefetch_Dir    : constant String := Target_Root & "/sitefetch";
      Sitefetchlib_Dir : constant String := Target_Root & "/sitefetchlib";
      Httpclient_Dir   : constant String := Target_Root & "/HttpClient";
   begin
      Validate_Staged_Release_Manifests (Target_Root);

      Manifest_Checks.Require_Staged_Crate_Source (Sitefetch_Dir, "sitefetch", "sitefetch.gpr", Quiet_Mode);
      Manifest_Checks.Require_Release_Dependencies
        (Sitefetch_Dir & "/alire.toml",
         [Ada.Strings.Unbounded.To_Unbounded_String ("sitefetchlib"),
          Ada.Strings.Unbounded.To_Unbounded_String ("i18n"),
          Ada.Strings.Unbounded.To_Unbounded_String ("terminal_styles"),
          Ada.Strings.Unbounded.To_Unbounded_String ("project_tools")],
         Quiet_Mode);

      Manifest_Checks.Require_Staged_Crate_Source (Sitefetchlib_Dir, "sitefetchlib", "sitefetchlib.gpr", Quiet_Mode);
      Manifest_Checks.Require_Release_Dependencies
        (Sitefetchlib_Dir & "/alire.toml",
         [Ada.Strings.Unbounded.To_Unbounded_String ("httpclient"),
          Ada.Strings.Unbounded.To_Unbounded_String ("regexp"),
          Ada.Strings.Unbounded.To_Unbounded_String ("zlib")],
         Quiet_Mode);

      Manifest_Checks.Require_Staged_Crate_Source (Httpclient_Dir, "httpclient", "httpclient.gpr", Quiet_Mode);
      Manifest_Checks.Require_Release_Dependency (Httpclient_Dir & "/alire.toml", "zlib", Quiet_Mode);

      declare
         Hygiene_Errors : Natural := 0;
      begin
         Project_Tools.Tree_Checks.Check_No_Generated_Python
           (Hygiene_Errors, Sitefetch_Dir, Quiet_Mode);
         Project_Tools.Tree_Checks.Check_No_Generated_Python
           (Hygiene_Errors, Sitefetchlib_Dir, Quiet_Mode);
         Project_Tools.Tree_Checks.Check_No_Generated_Python
           (Hygiene_Errors, Httpclient_Dir, Quiet_Mode);
         if Hygiene_Errors /= 0 then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            raise Program_Error;
         end if;
      end;

      if not Quiet_Mode then
         Put_Line ("validated staged release source under " & Target_Root);
      end if;
   end Validate_Staged_Release_Source;

   procedure Validate_Staged_Release_Build_Workspace (Target_Root : String) is
   begin
      Validate_Staged_Release_Source (Target_Root);

      File_Checks.Require_Directories
        ([Ada.Strings.Unbounded.To_Unbounded_String (Target_Root & "/zlib"),
          Ada.Strings.Unbounded.To_Unbounded_String (Target_Root & "/regexp"),
          Ada.Strings.Unbounded.To_Unbounded_String (Target_Root & "/i18n"),
          Ada.Strings.Unbounded.To_Unbounded_String (Target_Root & "/terminal_styles"),
          Ada.Strings.Unbounded.To_Unbounded_String (Target_Root & "/project_tools")],
         "staged release build missing dependency crate",
         Quiet_Mode);
      File_Checks.Require_Files
        ([Ada.Strings.Unbounded.To_Unbounded_String (Target_Root & "/zlib/alire.toml"),
          Ada.Strings.Unbounded.To_Unbounded_String (Target_Root & "/regexp/alire.toml"),
          Ada.Strings.Unbounded.To_Unbounded_String (Target_Root & "/i18n/alire.toml"),
          Ada.Strings.Unbounded.To_Unbounded_String (Target_Root & "/terminal_styles/alire.toml"),
          Ada.Strings.Unbounded.To_Unbounded_String (Target_Root & "/project_tools/alire.toml")],
         "staged release build missing dependency manifest",
         Quiet_Mode);

      Manifest_Checks.Require_Build_Overlay
        (Target_Root & "/HttpClient/alire.build.toml",
         Httpclient_Release_Template,
         [Ada.Strings.Unbounded.To_Unbounded_String ("zlib = { path = ""../zlib"" }")],
         Quiet_Mode);
      Manifest_Checks.Require_Build_Overlay
        (Target_Root & "/sitefetchlib/alire.build.toml",
         Sitefetchlib_Release_Template,
         [Ada.Strings.Unbounded.To_Unbounded_String ("httpclient = { path = ""../HttpClient"" }"),
          Ada.Strings.Unbounded.To_Unbounded_String ("regexp = { path = ""../regexp"" }"),
          Ada.Strings.Unbounded.To_Unbounded_String ("zlib = { path = ""../zlib"" }")],
         Quiet_Mode);
      Manifest_Checks.Require_Build_Overlay
        (Target_Root & "/sitefetch/alire.build.toml",
         Sitefetch_Release_Template,
         [Ada.Strings.Unbounded.To_Unbounded_String ("sitefetchlib = { path = ""../sitefetchlib"" }"),
          Ada.Strings.Unbounded.To_Unbounded_String ("i18n = { path = ""../i18n"" }"),
          Ada.Strings.Unbounded.To_Unbounded_String ("terminal_styles = { path = ""../terminal_styles"" }"),
          Ada.Strings.Unbounded.To_Unbounded_String ("project_tools = { path = ""../project_tools"" }")],
         Quiet_Mode);

      if not Quiet_Mode then
         Put_Line ("validated staged release build workspace under " & Target_Root);
      end if;
   end Validate_Staged_Release_Build_Workspace;

   procedure Activate_Build_Manifests (Target_Root : String) is
   begin
      Manifest_Checks.Activate_Build_Manifest (Target_Root & "/HttpClient", Quiet_Mode);
      Manifest_Checks.Activate_Build_Manifest (Target_Root & "/sitefetchlib", Quiet_Mode);
      Manifest_Checks.Activate_Build_Manifest (Target_Root & "/sitefetch", Quiet_Mode);
   end Activate_Build_Manifests;

   procedure Restore_Publish_Manifests (Target_Root : String) is
   begin
      Manifest_Checks.Restore_Publish_Manifest (Target_Root & "/sitefetch");
      Manifest_Checks.Restore_Publish_Manifest (Target_Root & "/sitefetchlib");
      Manifest_Checks.Restore_Publish_Manifest (Target_Root & "/HttpClient");
   end Restore_Publish_Manifests;

   procedure Run_Staged_Build
     (Label : String;
      Dir   : String)
   is
   begin
      Project_Tools.Release_Checks.Run
        (Label   => Label,
         Dir     => Dir,
         Program => Alr_Path,
         Args    => Build_Args,
         Quiet   => Quiet_Mode);
   exception
      when Program_Error =>
         if not Quiet_Mode then
            Put_Line
              (Standard_Error,
               "pin-free staged release builds require dependencies to resolve from the Alire index, "
               & "or an explicit release-local dependency staging strategy outside the published manifests");
         end if;
         raise;
   end Run_Staged_Build;

   procedure Run_Staged_Gnatprove
     (Label : String;
      Dir   : String)
   is
   begin
      Project_Tools.Release_Checks.Run
        (Label   => Label,
         Dir     => Dir,
         Program => Alr_Path,
         Args    => Gnatprove_Check_Args,
         Quiet   => Quiet_Mode);
   end Run_Staged_Gnatprove;

   procedure Validate_Staged_Release_Build (Target_Root : String) is
   begin
      Validate_Staged_Release_Build_Workspace (Target_Root);
      Activate_Build_Manifests (Target_Root);

      begin
         Run_Staged_Build ("build staged HttpClient release source", Target_Root & "/HttpClient");
         Run_Staged_Build ("build staged sitefetchlib release source", Target_Root & "/sitefetchlib");
         Run_Staged_Build ("build staged sitefetch release source", Target_Root & "/sitefetch");
         Run_Staged_Gnatprove ("prove staged sitefetch release source", Target_Root & "/sitefetch");
         Restore_Publish_Manifests (Target_Root);
      exception
         when others =>
            Restore_Publish_Manifests (Target_Root);
            raise;
      end;

      Validate_Staged_Release_Source (Target_Root);

      if not Quiet_Mode then
         Put_Line ("validated staged release builds under " & Target_Root);
      end if;
   end Validate_Staged_Release_Build;

   procedure Print_Usage is
   begin
      Put_Line ("usage:");
      Put_Line ("  check_sitefetch");
      Put_Line ("  check_sitefetch [--quiet] --prepare-release-manifests TARGET_DIR");
      Put_Line ("  check_sitefetch [--quiet] --prepare-release-source TARGET_DIR");
      Put_Line ("  check_sitefetch [--quiet] --prepare-release-build TARGET_DIR");
      Put_Line ("  check_sitefetch [--quiet] --validate-release-manifests TARGET_DIR");
      Put_Line ("  check_sitefetch [--quiet] --validate-release-source TARGET_DIR");
      Put_Line ("  check_sitefetch [--quiet] --validate-release-build-workspace TARGET_DIR");
      Put_Line ("  check_sitefetch [--quiet] --validate-release-build TARGET_DIR");
   end Print_Usage;

   procedure Require_Alire_GNAT_15 is
      Output : Ada.Strings.Unbounded.Unbounded_String;
      Status : Integer;
   begin
      Status :=
        Project_Tools.Processes.Run_Status
          (Label   => "GNAT 15 version check",
           Dir     => Root_Dir,
           Program => Alr_Path,
           Args    => GNAT_Version_Args,
           Output  => Output,
           Quiet   => Quiet_Mode);

      if Status /= 0 then
         Put_Line (Standard_Error, "could not run `alr exec -- gnatls --version`");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      elsif Ada.Strings.Fixed.Index (Ada.Strings.Unbounded.To_String (Output), "GNATLS 15.") = 0 then
         Put_Line
           (Standard_Error,
            "wrong Ada compiler: sitefetch validation must use Alire GNAT 15; got: "
            & Ada.Strings.Unbounded.To_String (Output));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   end Require_Alire_GNAT_15;

begin
   if Ada.Command_Line.Argument_Count /= 0
     and then not
       ((Ada.Command_Line.Argument_Count = 2
         and then Is_Command_Mode (Ada.Command_Line.Argument (1)))
        or else
        (Ada.Command_Line.Argument_Count = 3
         and then Quiet_Mode
         and then Is_Command_Mode (Ada.Command_Line.Argument (2))))
   then
      Print_Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   if not Ada.Directories.Exists (Root_Dir & "/sitefetch.gpr") then
      Put_Line (Standard_Error, "check_sitefetch must be run from the sitefetch crate root");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Require_Alire_GNAT_15;

   if Ada.Command_Line.Argument_Count > 0 then
      if Ada.Command_Line.Argument (Mode_Argument_Index) = "--prepare-release-manifests" then
         Prepare_Release_Manifests (Ada.Command_Line.Argument (Target_Argument_Index));
      elsif Ada.Command_Line.Argument (Mode_Argument_Index) = "--prepare-release-source" then
         Prepare_Release_Source (Ada.Command_Line.Argument (Target_Argument_Index));
      elsif Ada.Command_Line.Argument (Mode_Argument_Index) = "--prepare-release-build" then
         Prepare_Release_Build (Ada.Command_Line.Argument (Target_Argument_Index));
      elsif Ada.Command_Line.Argument (Mode_Argument_Index) = "--validate-release-manifests" then
         Validate_Staged_Release_Manifests (Ada.Command_Line.Argument (Target_Argument_Index));
      elsif Ada.Command_Line.Argument (Mode_Argument_Index) = "--validate-release-source" then
         Validate_Staged_Release_Source (Ada.Command_Line.Argument (Target_Argument_Index));
      elsif Ada.Command_Line.Argument (Mode_Argument_Index) = "--validate-release-build-workspace" then
         Validate_Staged_Release_Build_Workspace (Ada.Command_Line.Argument (Target_Argument_Index));
      else
         Validate_Staged_Release_Build (Ada.Command_Line.Argument (Target_Argument_Index));
      end if;
      return;
   end if;

   Run ("build sitefetch CLI crate", Root_Dir, Alr_Path, Build_Args);
   Run ("prove sitefetch release surface", Root_Dir, Alr_Path, Gnatprove_Check_Args);
   Run ("build sitefetch CLI tests", Root_Dir & "/tests", Alr_Path, Build_Args);
   Run ("run sitefetch CLI tests", Root_Dir & "/tests", Alr_Path, Exec_CLI_Tests_Args);

   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root_Dir & "/obj", Quiet_Mode);
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root_Dir & "/tests/obj", Quiet_Mode);

   New_Line;
   Put_Line ("Sitefetch check passed.");
exception
   when Program_Error =>
      null;
end Check_Sitefetch;
