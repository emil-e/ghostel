;;; ghostel-project-test.el --- Tests for ghostel: project -*- lexical-binding: t; -*-

;;; Commentary:

;; `ghostel-project` buffer naming, identity match, return-buffer semantics.

;;; Code:

(require 'ghostel-test-helpers)

(ert-deftest ghostel-test-project-buffer-name ()
  "Test that `ghostel-project' derives the buffer name correctly."
  (require 'project)
  (let ((ghostel-buffer-name "*ghostel*")
        result)
    (cl-letf (((symbol-function 'project-current)
               (lambda (_maybe-prompt) '(transient . "/tmp/myproj/")))
              ((symbol-function 'project-root)
               (lambda (proj) (cdr proj)))
              ((symbol-function 'project-prefixed-buffer-name)
               (lambda (name) (format "*myproj-%s*" name)))
              ((symbol-function 'ghostel)
               (lambda (&optional _)
                 (setq result (cons default-directory ghostel-buffer-name)))))
      (ghostel-project)
      (should (equal "/tmp/myproj/" (car result)))
      (should (string-match-p "ghostel" (cdr result)))
      (should-not (string-match-p "\\*\\*" (cdr result))))))

(ert-deftest ghostel-test-project-universal-arg ()
  "`ghostel-project' forwards the prefix arg AND binds `ghostel-buffer-name'.
The captured value of `ghostel-buffer-name' at `ghostel' call time
proves the project-prefixed binding actually took effect."
  (require 'project)
  ;; Numeric prefix arg (C-5 M-x ghostel-project)
  (let ((ghostel-buffer-name "*ghostel*")
        captured)
    (cl-letf (((symbol-function 'project-current)
               (lambda (_maybe-prompt) '(transient . "/tmp/myproj/")))
              ((symbol-function 'project-root)
               (lambda (proj) (cdr proj)))
              ((symbol-function 'project-prefixed-buffer-name)
               (lambda (name) (format "*myproj-%s*" name)))
              ((symbol-function 'ghostel)
               (lambda (&optional arg)
                 (setq captured (cons arg ghostel-buffer-name)))))
      (ghostel-project 4)
      (should (equal (car captured) 4))
      (should (equal (cdr captured) "*myproj-ghostel*"))))
  ;; Universal prefix arg (C-u M-x ghostel-project)
  (let ((ghostel-buffer-name "*ghostel*")
        captured)
    (cl-letf (((symbol-function 'project-current)
               (lambda (_maybe-prompt) '(transient . "/tmp/myproj/")))
              ((symbol-function 'project-root)
               (lambda (proj) (cdr proj)))
              ((symbol-function 'project-prefixed-buffer-name)
               (lambda (name) (format "*myproj-%s*" name)))
              ((symbol-function 'ghostel)
               (lambda (&optional arg)
                 (setq captured (cons arg ghostel-buffer-name)))))
      (ghostel-project '(4))
      (should (equal (car captured) '(4)))
      (should (equal (cdr captured) "*myproj-ghostel*")))))

(ert-deftest ghostel-test-reuses-identity-match-after-rename ()
  "`ghostel' reuses an identity-matched buffer after a title-tracking rename."
  (let* ((ghostel-buffer-name "*ghostel*")
         (existing (generate-new-buffer ghostel-buffer-name))
         (pre-count (length (buffer-list)))
         popped)
    (unwind-protect
        (progn
          (with-current-buffer existing
            (ghostel-mode)
            (setq-local ghostel--buffer-identity "*ghostel*")
            (setq-local ghostel--term 'fake-term))
          (with-current-buffer existing (rename-buffer "*ghostel: zsh*"))
          (cl-letf (((symbol-function 'ghostel--load-module) (lambda (&rest _) nil))
                    ((symbol-function 'pop-to-buffer)
                     (lambda (b &rest _) (setq popped b))))
            (ghostel))
          (should (buffer-live-p existing))
          (should (eq popped existing))
          (should (equal "*ghostel: zsh*" (buffer-name existing)))
          (should (= pre-count (length (buffer-list)))))
      (when (buffer-live-p existing) (kill-buffer existing)))))

(ert-deftest ghostel-test-project-reuses-identity-match-after-rename ()
  "`ghostel-project' reuses a project's buffer after title tracking renames it."
  (require 'project)
  (let* ((ghostel-buffer-name "*ghostel*")
         (project-name "*myproj-ghostel*")
         (existing (generate-new-buffer project-name))
         (pre-count (length (buffer-list)))
         popped)
    (unwind-protect
        (progn
          (with-current-buffer existing
            (ghostel-mode)
            (setq-local ghostel--buffer-identity project-name)
            (setq-local ghostel--term 'fake-term))
          (with-current-buffer existing (rename-buffer "*ghostel: zsh*"))
          (cl-letf (((symbol-function 'project-current)
                     (lambda (&optional _) '(transient . "/tmp/myproj/")))
                    ((symbol-function 'project-root)
                     (lambda (proj) (cdr proj)))
                    ((symbol-function 'project-prefixed-buffer-name)
                     (lambda (name) (format "*myproj-%s*" name)))
                    ((symbol-function 'ghostel--load-module) (lambda (&rest _) nil))
                    ((symbol-function 'pop-to-buffer)
                     (lambda (b &rest _) (setq popped b))))
            (ghostel-project))
          (should (buffer-live-p existing))
          (should (eq popped existing))
          (should (equal "*ghostel: zsh*" (buffer-name existing)))
          (should (= pre-count (length (buffer-list)))))
      (when (buffer-live-p existing) (kill-buffer existing)))))

(ert-deftest ghostel-test-init-buffer-sets-identity ()
  "`ghostel--init-buffer' records the identity passed to it."
  (let ((buf (generate-new-buffer " *ghostel-test-identity*")))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'ghostel--new) (lambda (&rest _) 'fake))
                    ((symbol-function 'ghostel--set-size) #'ignore)
                    ((symbol-function 'ghostel--apply-palette) (lambda (&rest _) nil)))
            (ghostel--init-buffer buf "*myproj-ghostel*"))
          (should (equal "*myproj-ghostel*"
                         (buffer-local-value 'ghostel--buffer-identity buf))))
      (kill-buffer buf))))

(ert-deftest ghostel-test-init-buffer-rejects-non-empty-buffer ()
  "`ghostel--init-buffer' only initializes empty buffers."
  (let ((buf (generate-new-buffer " *ghostel-test-nonempty*")))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (insert "existing text"))
          (should-error (ghostel--init-buffer buf) :type 'user-error))
      (kill-buffer buf))))

(ert-deftest ghostel-test-init-buffer-rejects-existing-terminal ()
  "`ghostel--init-buffer' signals instead of reinitializing a buffer."
  (let ((buf (generate-new-buffer " *ghostel-test-reinit*")))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (setq-local ghostel--term 'fake-term))
          (should-error (ghostel--init-buffer buf) :type 'user-error))
      (kill-buffer buf))))

(ert-deftest ghostel-test-create-initializes-buffer ()
  "`ghostel--create' creates a buffer and attaches its terminal through init."
  (let (buf)
    (unwind-protect
        (cl-letf (((symbol-function 'ghostel--new) (lambda (&rest _) 'fake-term))
                  ((symbol-function 'ghostel--set-size) #'ignore)
                  ((symbol-function 'ghostel--apply-palette) #'ignore))
          (setq buf (ghostel--create " *ghostel-test-create*" "identity" nil 7 33))
          (should (buffer-live-p buf))
          (with-current-buffer buf
            (should (derived-mode-p 'ghostel-mode))
            (should (eq ghostel--term 'fake-term))
            (should (= ghostel--term-rows 7))
            (should (= ghostel--term-cols 33))
            (should (equal ghostel--buffer-identity "identity"))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(ert-deftest ghostel-test-returns-buffer ()
  "`ghostel' returns the (live) Ghostel buffer."
  (let* ((ghostel-buffer-name "*ghostel-return-test*")
         result)
    (cl-letf (((symbol-function 'ghostel--load-module) (lambda (&rest _) nil))
              ((symbol-function 'ghostel--new) (lambda (&rest _) 'fake-term))
              ((symbol-function 'ghostel--set-size) #'ignore)
              ((symbol-function 'ghostel--apply-palette) #'ignore)
              ((symbol-function 'ghostel--start-process) #'ignore)
              ((symbol-function 'pop-to-buffer) (lambda (&rest _) nil)))
      (setq result (ghostel)))
    (should (bufferp result))
    (should (buffer-live-p result))
    (should (string-match-p "ghostel-return-test" (buffer-name result)))
    (kill-buffer result)))

(ert-deftest ghostel-test-project-returns-buffer ()
  "`ghostel-project' returns the (live) Ghostel buffer."
  (require 'project)
  (let* ((ghostel-buffer-name "*ghostel*")
         result)
    (cl-letf (((symbol-function 'project-current)
               (lambda (&optional _) '(transient . "/tmp/retproj/")))
              ((symbol-function 'project-root)
               (lambda (proj) (cdr proj)))
              ((symbol-function 'project-prefixed-buffer-name)
               (lambda (name) (format "*retproj-%s*" name)))
              ((symbol-function 'ghostel--load-module) (lambda (&rest _) nil))
              ((symbol-function 'ghostel--new) (lambda (&rest _) 'fake-term))
              ((symbol-function 'ghostel--set-size) #'ignore)
              ((symbol-function 'ghostel--apply-palette) #'ignore)
              ((symbol-function 'ghostel--start-process) #'ignore)
              ((symbol-function 'pop-to-buffer) (lambda (&rest _) nil)))
      (setq result (ghostel-project)))
    (should (bufferp result))
    (should (buffer-live-p result))
    (should (string-match-p "retproj" (buffer-name result)))
    (kill-buffer result)))

(ert-deftest ghostel-test-first-creation-respects-display-buffer-alist ()
  "First `ghostel' creation exposes `ghostel-mode' to display rules."
  (let ((saved (current-window-configuration))
        (origin (generate-new-buffer " *ghostel-test-origin*"))
        (ghostel-buffer-name "*ghostel-test-display*"))
    (unwind-protect
        (progn
          (delete-other-windows)
          (switch-to-buffer origin)
          (let ((display-buffer-alist
                 `((,(lambda (buf _action)
                       (with-current-buffer buf
                         (derived-mode-p 'ghostel-mode)))
                    (display-buffer-pop-up-window)))))
            (cl-letf (((symbol-function 'ghostel--load-module) #'ignore)
                      ((symbol-function 'ghostel--new)
                       (lambda (&rest _) 'fake-term))
                      ((symbol-function 'ghostel--set-size) #'ignore)
                      ((symbol-function 'ghostel--apply-palette) #'ignore)
                      ((symbol-function 'ghostel--start-process) #'ignore))
              (ghostel)))
          (let ((created (get-buffer ghostel-buffer-name)))
            (should (buffer-live-p created))
            (should (with-current-buffer created
                      (derived-mode-p 'ghostel-mode)))
            (should (get-buffer-window origin))
            (should (get-buffer-window created))
            (should (not (eq (get-buffer-window origin)
                             (get-buffer-window created))))))
      (when (get-buffer ghostel-buffer-name)
        (kill-buffer ghostel-buffer-name))
      (when (buffer-live-p origin)
        (kill-buffer origin))
      (set-window-configuration saved))))

(provide 'ghostel-project-test)
;;; ghostel-project-test.el ends here
