--  Write one fetch progress event to standard output.
--
--  @param Event Progress event kind to display.
--  @param URL URL associated with the progress event.
procedure Sitefetch.Progress
  (Event : Progress_Event;
   URL   : String);
