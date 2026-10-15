"""Local, editable duplicate review. No removal is available through the web viewer."""
import queue
from pathlib import Path
import threading
import tkinter as tk
from tkinter import messagebox, ttk

from mingomedia_core import Cancelled
from mingomedia_duplicates import apply_plans, find_duplicates, make_plan, recommend, summary


class DuplicateReview:
    def __init__(self, app, autostart=True):
        self.app = app
        self.window = tk.Toplevel(app.root)
        self.window.title('MingoMedia · Revisar duplicados')
        self.window.geometry('1000x720')
        self.window.minsize(760, 580)
        self.window.transient(app.root)
        self.window.protocol('WM_DELETE_WINDOW', self.close)
        self.cancel = threading.Event()
        self.events = queue.Queue()
        self.worker = None
        self.busy = False
        self.closed = False
        self.closing = False
        self.groups = ()
        self.selected = set()
        self.keepers = {}
        self.manual = set()
        self.reasons = {}
        self.drives = [drive for drive in app.drives if drive.letter in app.selected]
        self.preferred = tk.StringVar(value='Automático')
        self.status = tk.StringVar(value='Preparando revisión…')
        self.reason = tk.StringVar()
        panel = ttk.Frame(self.window, padding=16)
        panel.pack(fill='both', expand=True)
        ttk.Label(panel,text='Conservar una copia de cada archivo',font=('Segoe UI',16,'bold')).pack(anchor='w')
        ttk.Label(panel,text='Solo se agrupan archivos con contenido idéntico. Marca los grupos que quieras revisar.\nPuedes elegir qué copia conservar; las demás irán a la Papelera después de tu confirmación.',wraplength=900).pack(anchor='w',pady=(8,12))
        bar = ttk.Frame(panel)
        bar.pack(fill='x')
        ttk.Label(bar,text='Preferir unidad:').pack(side='left')
        preferred = ttk.Combobox(bar,textvariable=self.preferred,state='readonly',width=32,
                                values=['Automático']+[f'{drive.letter}: · {drive.kind}' for drive in self.drives])
        preferred.pack(side='left',padx=8)
        preferred.bind('<<ComboboxSelected>>',lambda event:self.choose_preference())
        ttk.Button(bar,text='Marcar todos',command=lambda:self.select_all(True)).pack(side='left',padx=4)
        ttk.Button(bar,text='Ninguno',command=lambda:self.select_all(False)).pack(side='left')
        self.tree = ttk.Treeview(panel,columns=('name','copies','size','keep','retire'),height=8,selectmode='browse')
        self.tree.heading('#0',text='Marcar')
        self.tree.column('#0',width=60,stretch=False)
        for key,title,width in [('name','Archivo',250),('copies','Copias',60),('size','A la Papelera',110),('keep','Conservar en',110),('retire','Retirar de',140)]:
            self.tree.heading(key,text=title)
            self.tree.column(key,width=width,minwidth=50)
        self.tree.pack(fill='both',expand=True,pady=(12,4))
        self.tree.bind('<Button-1>',self.toggle)
        self.tree.bind('<space>',self.toggle)
        self.tree.bind('<<TreeviewSelect>>',lambda event:self.show_copies())
        ttk.Label(panel,textvariable=self.reason,wraplength=900).pack(anchor='w',pady=5)
        copies_frame = ttk.Frame(panel)
        copies_frame.pack(fill='both',expand=True)
        self.copies = ttk.Treeview(copies_frame,columns=('action','drive','kind','path'),show='headings',height=6,selectmode='browse')
        for key,title,width in [('action','Acción',90),('drive','Unidad',60),('kind','Tipo de unidad',110),('path','Ruta completa',580)]:
            self.copies.heading(key,text=title)
            self.copies.column(key,width=width,minwidth=50,stretch=key=='path')
        self.copies.pack(side='left',fill='both',expand=True)
        scroll = ttk.Scrollbar(copies_frame,orient='vertical',command=self.copies.yview)
        scroll.pack(side='right',fill='y')
        self.copies.configure(yscrollcommand=scroll.set)
        horizontal = ttk.Scrollbar(panel,orient='horizontal',command=self.copies.xview)
        horizontal.pack(fill='x')
        self.copies.configure(xscrollcommand=horizontal.set)
        self.copies.bind('<Double-1>',lambda event:self.choose_keeper())
        ttk.Button(panel,text='Conservar la copia seleccionada',command=self.choose_keeper).pack(anchor='w',pady=6)
        self.progress = ttk.Progressbar(panel,maximum=100)
        self.progress.pack(fill='x',pady=4)
        ttk.Label(panel,textvariable=self.status,wraplength=900).pack(anchor='w',pady=4)
        footer = ttk.Frame(panel)
        footer.pack(fill='x')
        ttk.Button(footer,text='Cancelar / Cerrar',command=self.close).pack(side='left')
        self.review_button = ttk.Button(footer,text='Revisar retirada…',command=self.confirm)
        self.review_button.pack(side='right')
        self.review_button.configure(state='disabled')
        if autostart:
            app.busy = True
            app.dedup_dialog = self
            app.update_share_buttons()
            self.window.grab_set()
            self.start(self.discover)
        self.window.after(100,self.poll)

    def start(self, task):
        if self.busy:
            return
        self.cancel.clear()
        self.busy = True
        self.review_button.configure(state='disabled')
        def work():
            try:
                task()
            except Cancelled:
                self.events.put(('cancelled',None))
            except Exception as error:
                self.events.put(('error',str(error)))
            finally:
                self.events.put(('idle',None))
        self.worker = threading.Thread(target=work,daemon=True)
        self.app.worker = self.worker
        self.worker.start()

    def post(self, value):
        self.events.put(('progress',value))

    def discover(self):
        self.events.put(('groups',find_duplicates(self.app.result,self.post,self.cancel)))

    def load_groups(self, groups):
        self.groups = tuple(groups)
        self.selected.clear()
        self.keepers.clear()
        self.manual.clear()
        self.choose_preference()

    def choose_preference(self):
        if self.busy:
            return
        preferred = '' if self.preferred.get()=='Automático' else self.preferred.get()[0]
        for group in self.groups:
            if group.key not in self.manual:
                keep, reason = recommend(group,self.drives,preferred)
                self.keepers[group.key] = keep.key
                self.reasons[group.key] = reason
        self.render()

    def render(self):
        focus = self.tree.focus()
        self.tree.delete(*self.tree.get_children())
        for index,group in enumerate(self.groups):
            plan = make_plan(group,self.keepers[group.key])
            units = ', '.join(sorted({copy.drive+':' for copy in plan.retire}))
            self.tree.insert('', 'end',iid=str(index),text='☑' if group.key in self.selected else '☐',
                             values=(Path(plan.keep.path).name,len(group.copies),f'{group.reclaimable/1e6:.2f} MB',plan.keep.drive+':',units))
        if focus in self.tree.get_children():
            self.tree.focus(focus)
            self.tree.selection_set(focus)
        elif self.groups:
            self.tree.focus('0')
            self.tree.selection_set('0')
        self.show_copies()
        self.review_button.configure(state='normal' if self.selected and not self.busy else 'disabled')

    def toggle(self,event):
        if self.busy:
            return
        keyboard = getattr(event,'keysym','')=='space'
        if not keyboard and self.tree.identify_column(event.x)!='#0':
            return
        row = self.tree.focus() if keyboard else self.tree.identify_row(event.y)
        if row:
            self.selected.symmetric_difference_update({self.groups[int(row)].key})
            self.render()
        return 'break'

    def select_all(self, selected):
        if not self.busy:
            self.selected = {group.key for group in self.groups} if selected else set()
            self.render()

    def show_copies(self):
        self.copies.delete(*self.copies.get_children())
        rows = self.tree.selection()
        if not rows or not self.groups:
            self.reason.set('')
            return
        group = self.groups[int(rows[0])]
        kinds = {drive.letter:drive.kind for drive in self.drives}
        for index,copy in enumerate(group.copies):
            keep = copy.key==self.keepers[group.key]
            self.copies.insert('', 'end',iid=str(index),values=('CONSERVAR' if keep else 'Papelera',copy.drive+':',kinds.get(copy.drive,'Desconocido'),copy.path))
        self.reason.set('Elección manual' if group.key in self.manual else 'Propuesta: '+self.reasons[group.key]+'. Puedes cambiarla.')

    def choose_keeper(self):
        if self.busy or not self.tree.selection() or not self.copies.selection():
            return
        group = self.groups[int(self.tree.selection()[0])]
        copy = group.copies[int(self.copies.selection()[0])]
        self.keepers[group.key] = copy.key
        self.manual.add(group.key)
        self.render()

    def plans(self):
        return tuple(make_plan(group,self.keepers[group.key]) for group in self.groups if group.key in self.selected)

    def confirm(self):
        if self.busy:
            return
        plans = self.plans()
        if not plans:
            return
        review = tk.Toplevel(self.window)
        review.title('Confirmar rutas a conservar y retirar')
        review.geometry('900x600')
        review.transient(self.window)
        frame = ttk.Frame(review,padding=12)
        frame.pack(fill='both',expand=True)
        text = tk.Text(frame,wrap='word',font=('Consolas',10))
        text.pack(side='left',fill='both',expand=True)
        scroll = ttk.Scrollbar(frame,command=text.yview)
        scroll.pack(side='right',fill='y')
        text.configure(yscrollcommand=scroll.set)
        text.insert('1.0',summary(plans))
        text.configure(state='disabled')
        footer = ttk.Frame(review,padding=12)
        footer.pack(fill='x')
        def dismiss():
            review.destroy()
            self.window.grab_set()
        def execute():
            dismiss()
            self.status.set('Comprobando las copias antes de enviarlas a la Papelera…')
            self.start(lambda:self.events.put(('applied',apply_plans(self.app.result,plans,self.post,self.cancel))))
        review.protocol('WM_DELETE_WINDOW',dismiss)
        ttk.Button(footer,text='Volver y modificar',command=dismiss).pack(side='left')
        ttk.Button(footer,text='Confirmar y enviar a la Papelera',command=execute).pack(side='right')
        review.grab_set()

    def poll(self):
        if self.closed:
            return
        try:
            while True:
                kind,value = self.events.get_nowait()
                if kind=='progress':
                    total = value['total'] or 0
                    percent = value['processed']*100/total if total else 100
                    self.progress['value'] = percent
                    self.status.set(f"{percent:.0f}% · {value['processed']:,}/{total:,} archivos · {value['skipped']:,} omitidos")
                elif kind=='groups':
                    # The worker has finished using its snapshot; render after idle.
                    self.pending_groups = value
                elif kind=='applied':
                    self.app.result = value.result
                    if self.app.session:
                        self.app.session.result = value.result
                    self.groups = ()
                    self.selected.clear()
                    self.render()
                    self.app.show_page(4)
                    messagebox.showinfo('Revisión terminada',f'{value.recycled} copias enviadas a la Papelera.\n{value.skipped} omitidas por cambios, acceso o compatibilidad.\n'+('Operación cancelada.\n' if value.cancelled else '')+f'Informe: {value.journal}\n\nActualiza el navegador del móvil. Para otra revisión, cierra esta ventana y vuelve a abrirla.',parent=self.window)
                    self.status.set(f'Informe guardado en {value.journal}')
                elif kind=='error':
                    self.status.set(value)
                    messagebox.showerror('Revisión de duplicados',value,parent=self.window)
                elif kind=='cancelled':
                    self.status.set('Revisión cancelada.')
                elif kind=='idle':
                    self.busy = False
                    if hasattr(self,'pending_groups'):
                        groups,ignored = self.pending_groups
                        del self.pending_groups
                        self.load_groups(groups)
                        self.status.set(f'{len(groups):,} grupos con contenido idéntico · {ignored:,} omitidos. Marca los grupos que quieras retirar.')
                    self.review_button.configure(state='normal' if self.selected else 'disabled')
        except queue.Empty:
            pass
        if self.closing and (not self.worker or not self.worker.is_alive()):
            self.destroy()
            return
        self.window.after(100,self.poll)

    def close(self):
        self.cancel.set()
        self.closing = True
        self.status.set('Deteniendo la revisión. La copia conservada permanece protegida…')
        if not self.worker or not self.worker.is_alive():
            self.destroy()

    def destroy(self):
        self.closed = True
        self.app.busy = False
        if getattr(self.app,'dedup_dialog',None) is self:
            self.app.dedup_dialog = None
        self.window.destroy()
        self.app.update_share_buttons()
