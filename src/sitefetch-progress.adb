with Ada.Text_IO;

with Sitefetch.Progress_Format;

procedure Sitefetch.Progress
  (Event : Progress_Event;
   URL   : String)
is
begin
   case Event is
      when Progress_Failed =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            Sitefetch.Progress_Format.Format (Event, URL));
      when others =>
         Ada.Text_IO.Put_Line (Sitefetch.Progress_Format.Format (Event, URL));
   end case;
end Sitefetch.Progress;
