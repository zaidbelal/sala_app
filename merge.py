import os

output_file = "all_project_code.txt"
lib_dir = "lib"

with open(output_file, "w", encoding="utf-8") as outfile:
    for root, dirs, files in os.walk(lib_dir):
        for file in files:
            if file.endswith(".dart"):
                file_path = os.path.join(root, file)
                outfile.write(f"\n// {'='*50}\n")
                outfile.write(f"// FILE: {file_path}\n")
                outfile.write(f"// {'='*50}\n\n")
                with open(file_path, "r", encoding="utf-8", errors="ignore") as infile:
                    outfile.write(infile.read())
                    outfile.write("\n")

print("تم دمج الملفات بنجاح وبترميز UTF-8 سليم.")