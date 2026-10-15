"""MingoMedia: installable Windows drive, file-type and private-link wizard."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import queue
import sys
import threading
import tkinter as tk
from tkinter import messagebox, ttk
import uuid
import webbrowser

from mingomedia_core import (Cancelled, EXTENSIONS, VERSION, ShareSession, asset_directory,
                             data_directory, detect_drives, email_draft, prepare_web, scan)


class MingoMediaApp:
    def __init__(self, root, autodetect=True):
        self.root = root
        self.root.title('MingoMedia · Tu biblioteca privada')
        width = min(900,max(760,self.root.winfo_screenwidth()-80))
        height = min(740,max(600,self.root.winfo_screenheight()-100))
        self.root.geometry(f'{width}x{height}')
        self.root.minsize(760, 600)
        self.root.configure(bg='#f3f5fb')
        self.events = queue.Queue()
        self.cancel = threading.Event()
        self.drives = []
        self.selected = set()
        self.session = None
        self.result = None
        self.worker = None
        self.busy = False
        self.page = 0
        self.password = tk.StringVar()
        self.confirm = tk.StringVar()
        self.all_types = tk.BooleanVar(value=True)
        self.types = {key:tk.BooleanVar(value=False) for key in (*EXTENSIONS, 'otros')}
        self.personal = tk.BooleanVar(value=True)
        self.hashes = tk.BooleanVar(value=False)
        self.email = tk.StringVar()
        self.include_password = tk.BooleanVar(value=False)
        self.status = tk.StringVar()
        self.url = tk.StringVar()
        self.closed = False
        self.configure_style()
        self.shell = ttk.Frame(root, padding=28)
        self.shell.pack(fill='both',expand=True)
        ttk.Label(self.shell,text='MingoMedia',style='Title.TLabel').pack(anchor='w')
        ttk.Label(self.shell,text='Tus archivos, en tu ordenador. Tu biblioteca, también en el móvil.',style='Subtitle.TLabel').pack(anchor='w',pady=(4,22))
        self.steps = ttk.Label(self.shell)
        self.steps.pack(anchor='w',pady=(0,12))
        card = ttk.Frame(self.shell,style='Card.TFrame')
        card.pack(fill='both',expand=True)
        self.canvas = tk.Canvas(card,bg='white',highlightthickness=0,height=120)
        scrollbar = ttk.Scrollbar(card,orient='vertical',command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side='right',fill='y')
        self.canvas.pack(side='left',fill='both',expand=True)
        self.content = ttk.Frame(self.canvas,style='Card.TFrame',padding=22)
        self.content_window = self.canvas.create_window((0,0),window=self.content,anchor='nw')
        self.canvas.bind('<Configure>',self.resize_card)
        self.content.bind('<Configure>',lambda _event:self.canvas.configure(scrollregion=self.canvas.bbox('all')))
        self.root.bind('<MouseWheel>',self.scroll_card,add='+')
        self.footer = ttk.Frame(self.shell)
        self.footer.pack(fill='x',pady=(16,0))
        self.root.protocol('WM_DELETE_WINDOW',self.close)
        self.show_page(0)
        self.root.after(100,self.poll)
        if autodetect:
            self.refresh_drives()

    def configure_style(self):
        style = ttk.Style(self.root)
        style.theme_use('clam')
        style.configure('.',font=('Segoe UI',11),background='#f3f5fb',foreground='#18233c')
        style.configure('TFrame',background='#f3f5fb')
        style.configure('Card.TFrame',background='#ffffff')
        style.configure('Title.TLabel',font=('Segoe UI',26,'bold'))
        style.configure('Subtitle.TLabel',foreground='#58677f')
        style.configure('Heading.TLabel',font=('Segoe UI',17,'bold'),background='white')
        style.configure('Card.TLabel',background='white')
        style.configure('TButton',padding=(16,10))
        style.configure('Accent.TButton',background='#2563eb',foreground='white')
        style.map('Accent.TButton',background=[('active','#1d4ed8')])
        style.configure('TCheckbutton',background='white',padding=(0,6))
        style.configure('Treeview',rowheight=35,fieldbackground='white',background='white')
        style.configure('Treeview.Heading',font=('Segoe UI',10,'bold'),padding=8)
        style.configure('Horizontal.TProgressbar',background='#2563eb',troughcolor='#dbe5fa')

    def label(self,text,style='Card.TLabel',**options):
        label = ttk.Label(self.content,text=text,style=style,wraplength=740,**options)
        label.pack(anchor='w',pady=(0,12))
        return label

    def scroll_card(self,event):
        if not isinstance(event.widget,ttk.Treeview):
            self.canvas.yview_scroll(-int(event.delta/120),'units')

    def resize_card(self,_event=None):
        width = self.canvas.winfo_width()
        self.canvas.itemconfigure(self.content_window,width=width)
        for child in self.content.winfo_children():
            if isinstance(child,ttk.Label):
                child.configure(wraplength=max(320,width-44))

    def button(self,parent,text,command,accent=False,**options):
        button = ttk.Button(parent,text=text,command=command,style='Accent.TButton' if accent else 'TButton',**options)
        return button

    def show_page(self,page):
        self.page = page
        self.canvas.yview_moveto(0)
        for parent in (self.content,self.footer):
            for child in parent.winfo_children():
                child.destroy()
        names = ['1 · Unidades','2 · Archivos','3 · Contraseña','4 · Analizar y compartir','Tu biblioteca está preparada']
        self.steps.configure(text=names[page])
        if page == 0:
            self.page_drives()
        elif page == 1:
            self.page_types()
        elif page == 2:
            self.page_password()
        elif page == 3:
            self.page_progress()
        else:
            self.page_share()
        if page in (1,2):
            self.button(self.footer,'Atrás',lambda:self.show_page(page-1)).pack(side='left')
        if page < 3:
            self.next_button = self.button(self.footer,'Empezar análisis' if page == 2 else 'Siguiente →',self.next,True)
            self.next_button.pack(side='right')
        self.root.after_idle(self.resize_card)

    def page_drives(self):
        self.label('¿Qué unidades quieres analizar?','Heading.TLabel')
        self.label('Selecciona una, varias o todas. Solo aparecen las unidades conectadas y disponibles.')
        table = ttk.Frame(self.content,style='Card.TFrame')
        table.pack(fill='both',expand=True)
        self.tree = ttk.Treeview(table,columns=('name','kind','size','free'),show='tree headings',height=7,selectmode='none')
        for column,text,width in (('#0','Elegir',65),('name','Unidad',245),('kind','Tipo',145),('size','Capacidad',115),('free','Libre',100)):
            self.tree.heading(column,text=text)
            self.tree.column(column,width=width,minwidth=55,stretch=(column=='name'))
        scrollbar = ttk.Scrollbar(table,orient='vertical',command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        self.tree.pack(fill='both',expand=True,side='left')
        scrollbar.pack(fill='y',side='right')
        self.tree.bind('<ButtonRelease-1>',self.toggle_drive)
        self.tree.bind('<space>',self.toggle_drive)
        controls = ttk.Frame(self.content,style='Card.TFrame')
        controls.pack(fill='x',pady=14)
        self.button(controls,'Seleccionar todas',lambda:self.select_drives(True)).pack(side='left',padx=(0,8))
        self.button(controls,'Ninguna',lambda:self.select_drives(False)).pack(side='left')
        self.refresh_button = self.button(controls,'Actualizar unidades',self.refresh_drives)
        self.refresh_button.pack(side='right')
        ttk.Label(self.content,textvariable=self.status,style='Card.TLabel',wraplength=730).pack(anchor='w')
        self.render_drives()

    def render_drives(self):
        if self.page != 0:
            return
        for row in self.tree.get_children():
            self.tree.delete(row)
        for drive in self.drives:
            name = f'{drive.letter}:  {drive.label or "Sin etiqueta"}'
            self.tree.insert('', 'end',iid=drive.letter,text='☑' if drive.letter in self.selected else '☐',
                             values=(name,drive.kind,f'{drive.size/1e9:.1f} GB',f'{drive.free/1e9:.1f} GB'))

    def refresh_drives(self):
        if self.busy:
            return
        self.status.set('Detectando unidades disponibles…')
        if self.page == 0:
            self.refresh_button.configure(state='disabled')
        def work():
            try:
                self.events.put(('drives',detect_drives()))
            except Exception:
                self.events.put(('drive_error','No se pudieron detectar las unidades. Pulsa Actualizar unidades para reintentar.'))
        threading.Thread(target=work,daemon=True).start()

    def toggle_drive(self,event):
        row = self.tree.focus() if event.keysym == 'space' else self.tree.identify_row(event.y)
        if row:
            self.selected.symmetric_difference_update({row})
            self.render_drives()
            self.tree.focus(row)

    def select_drives(self,all_selected):
        self.selected = {drive.letter for drive in self.drives} if all_selected else set()
        self.render_drives()

    def page_types(self):
        self.label('¿Qué quieres encontrar?','Heading.TLabel')
        self.label('Puedes combinar los tipos que necesites: imágenes y vídeos, documentos y audio…')
        ttk.Checkbutton(self.content,text='Todos los tipos de archivo',variable=self.all_types,command=self.update_types).pack(anchor='w')
        self.type_buttons = []
        for key,title in (('imagenes','Imágenes'),('videos','Vídeos'),('audio','Audio'),('documentos','Documentos'),('otros','Otros archivos')):
            control = ttk.Checkbutton(self.content,text=title,variable=self.types[key])
            control.pack(anchor='w',padx=(24,0))
            self.type_buttons.append(control)
        ttk.Separator(self.content).pack(fill='x',pady=12)
        ttk.Checkbutton(self.content,text='Omitir Windows, programas y cachés (recomendado)',variable=self.personal).pack(anchor='w')
        ttk.Checkbutton(self.content,text='Comprobar contenido para identificar duplicados (más lento)',variable=self.hashes).pack(anchor='w')
        self.update_types()

    def update_types(self):
        for control in self.type_buttons:
            control.configure(state='disabled' if self.all_types.get() else 'normal')

    def page_password(self):
        self.label('Elige tu contraseña privada','Heading.TLabel')
        self.label('La necesitarás para entrar desde el móvil. Usa al menos 16 caracteres; puede ser una frase que recuerdes.')
        entries = []
        for title,variable in (('Contraseña',self.password),('Repite la contraseña',self.confirm)):
            self.label(title)
            entry = ttk.Entry(self.content,textvariable=variable,show='●',width=48,font=('Segoe UI',13))
            entry.pack(anchor='w',pady=(0,18),ipady=6)
            entries.append(entry)
        visible = tk.BooleanVar(value=False)
        ttk.Checkbutton(self.content,text='Mostrar contraseña',variable=visible,
                        command=lambda:[entry.configure(show='' if visible.get() else '●') for entry in entries]).pack(anchor='w')
        self.label('El análisis solo lee archivos. Al terminar, el enlace permitirá ver los archivos seleccionados mientras MingoMedia y el ordenador sigan encendidos y conectados.')
        entries[0].focus_set()

    def categories(self):
        return {'todos'} if self.all_types.get() else {key for key,value in self.types.items() if value.get()}

    def next(self):
        if self.page == 0:
            if not self.selected:
                return messagebox.showinfo('Elige una unidad','Selecciona al menos una unidad.',parent=self.root)
            self.show_page(1)
        elif self.page == 1:
            if not self.categories():
                return messagebox.showinfo('Elige archivos','Marca uno o varios tipos de archivo.',parent=self.root)
            self.show_page(2)
        elif self.page == 2:
            if len(self.password.get()) < 16:
                return messagebox.showinfo('Contraseña','Usa al menos 16 caracteres.',parent=self.root)
            if self.password.get() != self.confirm.get():
                return messagebox.showinfo('Contraseña','Las contraseñas no coinciden.',parent=self.root)
            self.start_scan()

    def page_progress(self):
        self.label('Preparando tu biblioteca','Heading.TLabel')
        self.label('Primero se cuentan los archivos seleccionados. Después verás el porcentaje real de análisis.')
        self.progress = ttk.Progressbar(self.content,mode='indeterminate',maximum=100)
        self.progress.pack(fill='x',pady=(32,18))
        self.progress.start(12)
        self.progress_text = ttk.Label(self.content,text='Buscando archivos…',style='Heading.TLabel')
        self.progress_text.pack(anchor='w',pady=10)
        ttk.Label(self.content,textvariable=self.status,style='Card.TLabel',wraplength=730).pack(anchor='w')
        self.cancel_button = self.button(self.footer,'Cancelar',self.cancel_work)
        self.cancel_button.pack(side='right')

    def start_scan(self):
        if self.busy:
            return
        if self.session:
            self.session.close()
            self.session = None
        self.cancel.clear()
        self.busy = True
        chosen = [drive for drive in self.drives if drive.letter in self.selected]
        categories = self.categories()
        password = self.password.get()
        personal,hashes = self.personal.get(),self.hashes.get()
        self.show_page(3)
        def work():
            try:
                assets = asset_directory()
                source = assets/'web'
                if not source.is_dir():
                    raise RuntimeError('Faltan los recursos del programa. Reinstala MingoMedia o prepara los recursos de desarrollo.')
                ready = {drive.letter:drive for drive in detect_drives()}
                if not all(drive.letter in ready for drive in chosen):
                    raise RuntimeError('Una unidad seleccionada se ha desconectado. Vuelve a elegir las unidades.')
                run = data_directory()/'analisis'/(datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8])
                prepare_web(source,run)
                result = scan([ready[d.letter] for d in chosen],categories,run,self.post_progress,self.cancel,personal,hashes)
                self.events.put(('scanned',result))
                if not result.count:
                    self.events.put(('empty',result))
                    return
                self.session = ShareSession(result,chosen,password,assets,self.cancel,self.post_progress)
                self.session.start_local()
                self.events.put(('local',self.session.local_url))
                try:
                    self.session.start_tunnel()
                except Exception as error:
                    self.session.stop_tunnel()
                    if isinstance(error,Cancelled):
                        raise
                    self.events.put(('share_error',str(error)))
            except Cancelled:
                if self.session:
                    self.session.close()
                    self.session = None
                self.events.put(('cancelled',None))
            except Exception as error:
                self.events.put(('error',str(error)))
            finally:
                self.events.put(('idle',None))
        self.worker = threading.Thread(target=work,daemon=True)
        self.worker.start()

    def post_progress(self,value):
        self.events.put(('progress',value))

    def cancel_work(self):
        self.cancel.set()
        self.status.set('Cancelando. Tus archivos no se modifican…')
        self.cancel_button.configure(state='disabled')

    def page_share(self):
        self.label('Tu biblioteca, lista para abrir','Heading.TLabel')
        if self.result:
            self.label(f'{self.result.count:,} archivos · {self.result.bytes/1e9:.2f} GB · {self.result.skipped:,} elementos omitidos por acceso o disponibilidad')
        self.label('Enlace privado para el móvil')
        self.url_entry = ttk.Entry(self.content,textvariable=self.url,state='readonly',font=('Segoe UI',11))
        self.url_entry.pack(fill='x',ipady=8,pady=(0,12))
        actions = ttk.Frame(self.content,style='Card.TFrame')
        actions.pack(fill='x',pady=(0,16))
        self.open_button = self.button(actions,'Abrir biblioteca',self.open_viewer,True)
        self.open_button.pack(side='left',padx=(0,8))
        self.copy_button = self.button(actions,'Copiar enlace',self.copy_link)
        self.copy_button.pack(side='left',padx=(0,8))
        self.retry_button = self.button(actions,'Reintentar enlace',self.retry_tunnel)
        self.retry_button.pack(side='left')
        self.label('Compartir por correo')
        row = ttk.Frame(self.content,style='Card.TFrame')
        row.pack(fill='x')
        ttk.Entry(row,textvariable=self.email,width=35).pack(side='left',fill='x',expand=True,ipady=7,padx=(0,10))
        self.mail_button = self.button(row,'Preparar correo',self.mail)
        self.mail_button.pack(side='right')
        ttk.Checkbutton(self.content,text='Incluir la contraseña en el borrador',variable=self.include_password).pack(anchor='w',pady=(8,0))
        self.label('Se abrirá tu aplicación de correo con un borrador para que lo envíes tú. Puedes compartir la contraseña por separado.')
        ttk.Label(self.content,textvariable=self.status,style='Card.TLabel',wraplength=730).pack(anchor='w',pady=8)
        self.label('Deja MingoMedia abierto y el PC encendido y conectado. El enlace es temporal y cambiará al crear una conexión nueva.')
        self.button(self.footer,'Nuevo análisis',self.new_scan).pack(side='left')
        self.button(self.footer,'Cerrar acceso',self.stop_sharing).pack(side='right')
        self.update_share_buttons()

    def update_share_buttons(self):
        if self.page != 4:
            return
        remote = bool(self.session and self.session.url)
        self.open_button.configure(state='normal' if self.session else 'disabled')
        for button in (self.copy_button,self.mail_button):
            button.configure(state='normal' if remote else 'disabled')
        self.retry_button.configure(state='disabled' if self.busy or remote or not self.session else 'normal')

    def retry_tunnel(self):
        if self.busy or not self.session:
            return
        self.busy = True
        self.cancel.clear()
        self.status.set('Conectando de nuevo…')
        self.update_share_buttons()
        def work():
            try:
                self.session.start_tunnel()
            except Exception as error:
                self.session.stop_tunnel()
                self.events.put(('share_error',str(error)))
            finally:
                self.events.put(('idle',None))
        self.worker = threading.Thread(target=work,daemon=True)
        self.worker.start()

    def open_viewer(self):
        if self.session:
            webbrowser.open(self.session.url or self.session.local_url)

    def copy_link(self):
        if self.session and self.session.url:
            self.root.clipboard_clear()
            self.root.clipboard_append(self.session.url)
            self.status.set('Enlace copiado.')

    def mail(self):
        if not self.session or not self.session.url:
            return
        try:
            uri = email_draft(self.email.get().strip(),self.session.url,
                              self.password.get() if self.include_password.get() else None)
            if not webbrowser.open(uri):
                self.status.set('Configura una aplicación de correo o usa Copiar enlace para compartirlo.')
        except ValueError as error:
            messagebox.showinfo('Correo',str(error),parent=self.root)

    def stop_sharing(self):
        self.cancel.set()
        if self.worker and self.worker.is_alive():
            self.status.set('Cerrando acceso…')
            self.root.after(200,self.stop_sharing)
            return
        if self.session:
            self.session.close()
            self.session = None
        self.url.set('Acceso cerrado')
        self.status.set('El enlace ya no está disponible. El análisis sigue guardado en este ordenador.')
        self.update_share_buttons()

    def new_scan(self):
        if self.busy:
            return
        if self.session:
            self.session.close()
            self.session = None
        self.url.set('')
        self.password.set('')
        self.confirm.set('')
        self.result = None
        self.show_page(0)
        self.refresh_drives()

    def poll(self):
        if self.closed:
            return
        try:
            while True:
                kind,value = self.events.get_nowait()
                if kind == 'drives':
                    self.drives = value
                    self.selected.intersection_update({d.letter for d in value})
                    self.status.set(f'{len(value)} unidades disponibles. Marca las que quieras analizar.' if value else 'No hay unidades disponibles.')
                    self.render_drives()
                    if self.page == 0:
                        self.refresh_button.configure(state='normal')
                elif kind == 'drive_error':
                    self.status.set(value)
                    if self.page == 0:
                        self.refresh_button.configure(state='normal')
                elif kind == 'progress':
                    phase = value['phase']
                    if phase == 'shared':
                        self.url.set(value['url'])
                        self.status.set('Enlace privado activo. Entra con la contraseña que elegiste.')
                        self.show_page(4)
                    elif self.page == 3:
                        if phase == 'discover':
                            self.status.set(f"{value['processed']:,} archivos seleccionados encontrados…")
                        else:
                            self.progress.stop()
                            self.progress.configure(mode='determinate')
                            total = value['total'] or 0
                            percent = (100*value['processed']/total) if total else 100
                            self.progress['value'] = percent
                            self.progress_text.configure(text=f'{percent:.0f}% analizado')
                            self.status.set('Análisis terminado. Preparando enlace privado…' if phase == 'done' else f"{value['processed']:,} / {total:,} archivos · {value['skipped']:,} omitidos")
                elif kind == 'scanned':
                    self.result = value
                elif kind == 'local':
                    self.status.set('Biblioteca local preparada. Conectando el enlace para el móvil…')
                elif kind == 'share_error':
                    self.url.set('Sin conexión remota; biblioteca disponible en este PC')
                    self.status.set(value)
                    self.show_page(4)
                elif kind == 'empty':
                    self.show_page(1)
                    messagebox.showinfo('Sin archivos','No se encontraron archivos con esa selección. Elige otros tipos o unidades.',parent=self.root)
                elif kind == 'cancelled':
                    self.status.set('Análisis cancelado.')
                    self.show_page(0)
                elif kind == 'error':
                    self.show_page(0)
                    self.status.set(value)
                    messagebox.showerror('MingoMedia',value,parent=self.root)
                elif kind == 'idle':
                    self.busy = False
                    self.update_share_buttons()
        except queue.Empty:
            pass
        # A dead tunnel must never leave a stale "active" state in the wizard.
        if self.page == 4 and self.session and self.session.url and self.session.tunnel and self.session.tunnel.poll() is not None:
            self.session.stop_tunnel()
            self.url.set('Enlace desconectado')
            self.status.set('La conexión se ha cerrado. Puedes reintentar sin volver a analizar.')
            self.update_share_buttons()
        self.root.after(100,self.poll)

    def close(self):
        if (self.busy or self.session) and not messagebox.askyesno('Cerrar MingoMedia','Se detendrá el análisis y se cerrará el acceso desde el móvil. ¿Cerrar?',parent=self.root):
            return
        self.cancel.set()
        def finish():
            if self.worker and self.worker.is_alive():
                self.root.after(100,finish)
                return
            if self.session:
                self.session.close()
            self.closed = True
            self.password.set('')
            self.confirm.set('')
            self.root.destroy()
        finish()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test',type=Path,help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.self_test:
        # Frozen-runtime smoke check: no drive scanning, network, or user data.
        root = tk.Tk()
        root.withdraw()
        app = MingoMediaApp(root,autodetect=False)
        screens = []
        for page in range(5):
            app.show_page(page)
            root.update_idletasks()
            screens.append({'page':page,'widgets':len(app.content.winfo_children()),
                            'required_height':root.winfo_reqheight(),'height':root.winfo_height()})
        app.closed = True
        assets = asset_directory()
        result = {'version':VERSION,'tk':str(root.tk.call('info','patchlevel')),
                  'web':all((assets/'web'/name).is_file() for name in ('index.html','assets/js/picker.js')),
                  'tunnel':(assets/'cloudflared.exe').is_file(),'screens':screens}
        args.self_test.write_text(json.dumps(result),encoding='utf-8')
        root.destroy()
        return
    root = tk.Tk()
    MingoMediaApp(root)
    root.mainloop()


if __name__ == '__main__':
    main()
