with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

package body Sitefetch.App_Format
  with SPARK_Mode => On
is
   use Ada.Strings.Unbounded;

   function Natural_Image (Value : Natural) return String is
   begin
      return Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Left);
   end Natural_Image;

   function JSON_Escape (Text : String) return String is
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      for Ch of Text loop
         case Ch is
            when '"' =>
               Append (Result, Character'Val (92));
               Append (Result, '"');
            when Character'Val (92) =>
               Append (Result, Character'Val (92));
               Append (Result, Character'Val (92));
            when Character'Val (8) =>
               Append (Result, "\b");
            when Character'Val (9) =>
               Append (Result, "\t");
            when Character'Val (10) =>
               Append (Result, "\n");
            when Character'Val (12) =>
               Append (Result, "\f");
            when Character'Val (13) =>
               Append (Result, "\r");
            when others =>
               if Character'Pos (Ch) < 32 then
                  Append (Result, "\u00");
                  declare
                     Value : constant Natural := Character'Pos (Ch);
                     Hex   : constant String := "0123456789abcdef";
                  begin
                     Append (Result, Hex (Hex'First + Value / 16));
                     Append (Result, Hex (Hex'First + Value mod 16));
                  end;
               else
                  Append (Result, Ch);
               end if;
         end case;
      end loop;

      return To_String (Result);
   end JSON_Escape;

   function JSON_String (Text : String) return String is
   begin
      return '"' & JSON_Escape (Text) & '"';
   end JSON_String;

   function JSON_Boolean (Value : Boolean) return String is
   begin
      if Value then
         return "true";
      else
         return "false";
      end if;
   end JSON_Boolean;

   function Cache_Decision_For (Event : Sitefetch.Progress_Event) return String is
   begin
      case Event is
         when Sitefetch.Progress_Cache_Revalidate => return "revalidate";
         when Sitefetch.Progress_Cache_Reused => return "reused";
         when Sitefetch.Progress_Cache_Rejected => return "rejected";
         when others => return "";
      end case;
   end Cache_Decision_For;

   function Robots_Source_For (Event : Sitefetch.Progress_Event) return String is
   begin
      case Event is
         when Sitefetch.Progress_Robots_Allowed | Sitefetch.Progress_Robots_Disallowed
            | Sitefetch.Progress_Robots_Loaded | Sitefetch.Progress_Robots_Failed =>
            return "robots.txt";
         when others => return "";
      end case;
   end Robots_Source_For;

   function Progress_Event_Name (Event : Sitefetch.Progress_Event) return String is
   begin
      case Event is
         when Sitefetch.Progress_Fetching => return "fetching";
         when Sitefetch.Progress_Written => return "written";
         when Sitefetch.Progress_Skipped_External => return "skipped_external";
         when Sitefetch.Progress_Skipped_Unsupported => return "skipped_unsupported";
         when Sitefetch.Progress_Warning_Dangerous => return "warning_dangerous";
         when Sitefetch.Progress_Skipped_Dangerous => return "skipped_dangerous";
         when Sitefetch.Progress_Already_Visited => return "already_visited";
         when Sitefetch.Progress_Skipped_Limit => return "skipped_limit";
         when Sitefetch.Progress_Cache_Revalidate => return "cache_revalidate";
         when Sitefetch.Progress_Cache_Reused => return "cache_reused";
         when Sitefetch.Progress_Cache_Rejected => return "cache_rejected";
         when Sitefetch.Progress_Resume_Attempt => return "resume_attempt";
         when Sitefetch.Progress_Retry => return "retry";
         when Sitefetch.Progress_Robots_Allowed => return "robots_allowed";
         when Sitefetch.Progress_Robots_Disallowed => return "robots_disallowed";
         when Sitefetch.Progress_Robots_Loaded => return "robots_loaded";
         when Sitefetch.Progress_Robots_Failed => return "robots_failed";
         when Sitefetch.Progress_Failed => return "failed";
         when Sitefetch.Progress_Redirected => return "redirected";
      end case;
   end Progress_Event_Name;
end Sitefetch.App_Format;
