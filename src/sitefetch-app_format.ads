package Sitefetch.App_Format
  with SPARK_Mode => On
is
   function Natural_Image (Value : Natural) return String;

   function JSON_Escape (Text : String) return String;

   function JSON_String (Text : String) return String;

   function JSON_Boolean (Value : Boolean) return String;

   function Cache_Decision_For (Event : Sitefetch.Progress_Event) return String;

   function Robots_Source_For (Event : Sitefetch.Progress_Event) return String;

   function Progress_Event_Name (Event : Sitefetch.Progress_Event) return String;
end Sitefetch.App_Format;
