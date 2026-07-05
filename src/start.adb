with Ada.Command_Line;

with Sitefetch.App;
with Sitefetch.CLI;

procedure Start is
   use type Sitefetch.App.Exit_Status;

   Status : constant Sitefetch.App.Exit_Status :=
     Sitefetch.App.Run (Sitefetch.CLI.Parse_Command_Line);
begin
   if Status = Sitefetch.App.Exit_Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Start;
