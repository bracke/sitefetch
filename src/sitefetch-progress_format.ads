package Sitefetch.Progress_Format is
   --  Format one fetch progress event for terminal output.
   --
   --  @param Event Progress event kind to format.
   --  @param URL URL associated with the progress event.
   --  @return Marked and decorated progress line.
   function Format
     (Event : Progress_Event;
      URL   : String) return String;
end Sitefetch.Progress_Format;
