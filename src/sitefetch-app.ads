with Sitefetch.CLI;

package Sitefetch.App is
   type Exit_Status is (Exit_Success, Exit_Failure);

   type Line_Sink is access procedure (Line : String);

   type Website_Fetcher is not null access function
     (URL              : String;
      Target_Directory : String;
      Statistics       : out Sitefetch.Fetch_Statistics;
      Progress         : Sitefetch.Progress_Callback;
      Options          : Sitefetch.Fetch_Options) return Boolean;

   --  Execute sitefetch command-line behavior from already parsed options.
   --
   --  @param Options Parsed command-line options.
   --  @param Fetcher Website fetch implementation to call for ordinary fetches.
   --  @param Output Output sink for ordinary output lines.
   --  @param Error_Output Output sink for diagnostic output lines.
   --  @return Exit status that should be reported by the executable.
   function Run
     (Options      : Sitefetch.CLI.Parsed_Options;
      Fetcher      : Website_Fetcher;
      Output       : Line_Sink;
      Error_Output : Line_Sink) return Exit_Status;

   --  Execute sitefetch command-line behavior using the production fetcher.
   --
   --  @param Options Parsed command-line options.
   --  @param Output Output sink for ordinary output lines.
   --  @param Error_Output Output sink for diagnostic output lines.
   --  @return Exit status that should be reported by the executable.
   function Run
     (Options      : Sitefetch.CLI.Parsed_Options;
      Output       : Line_Sink;
      Error_Output : Line_Sink) return Exit_Status;

   --  Execute sitefetch command-line behavior using production fetch and console output.
   --
   --  @param Options Parsed command-line options.
   --  @return Exit status that should be reported by the executable.
   function Run (Options : Sitefetch.CLI.Parsed_Options) return Exit_Status;
end Sitefetch.App;
