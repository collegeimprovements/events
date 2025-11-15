/**
 * Base UI Components - JavaScript Hooks
 *
 * These hooks provide interactive functionality for Phoenix LiveView components.
 */

// Select component hook
export const Select = {
  mounted() {
    this.handleClickOutside = (e) => {
      if (!this.el.contains(e.target)) {
        const dropdown = this.el.querySelector('[role="listbox"]');
        if (dropdown && !dropdown.classList.contains('hidden')) {
          dropdown.classList.add('hidden');
        }
      }
    };
    document.addEventListener('click', this.handleClickOutside);
  },
  destroyed() {
    document.removeEventListener('click', this.handleClickOutside);
  }
};

// Slider component hook
export const Slider = {
  mounted() {
    const input = this.el.querySelector('input[type="range"]');
    if (!input) return;

    this.handleInput = () => {
      const value = input.value;
      const min = input.min || 0;
      const max = input.max || 100;
      const percentage = ((value - min) / (max - min)) * 100;

      // Update background gradient
      input.style.background = `linear-gradient(to right, #18181b 0%, #18181b ${percentage}%, #e4e4e7 ${percentage}%, #e4e4e7 100%)`;
    };

    input.addEventListener('input', this.handleInput);
    this.handleInput(); // Initial call
  },
  destroyed() {
    const input = this.el.querySelector('input[type="range"]');
    if (input) {
      input.removeEventListener('input', this.handleInput);
    }
  }
};

// InputOTP component hook
export const InputOTP = {
  mounted() {
    const inputs = this.el.querySelectorAll('input');

    inputs.forEach((input, index) => {
      // Auto-focus next input on value entry
      input.addEventListener('input', (e) => {
        if (e.target.value.length === 1 && index < inputs.length - 1) {
          inputs[index + 1].focus();
        }
      });

      // Handle backspace
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Backspace' && !e.target.value && index > 0) {
          inputs[index - 1].focus();
        }
      });

      // Only allow numbers/letters
      input.addEventListener('beforeinput', (e) => {
        if (e.data && !/^[a-zA-Z0-9]$/.test(e.data)) {
          e.preventDefault();
        }
      });

      // Handle paste
      input.addEventListener('paste', (e) => {
        e.preventDefault();
        const pastedData = e.clipboardData.getData('text');
        const chars = pastedData.split('').slice(0, inputs.length);

        chars.forEach((char, i) => {
          if (inputs[i] && /^[a-zA-Z0-9]$/.test(char)) {
            inputs[i].value = char;
            if (i < inputs.length - 1) {
              inputs[i + 1].focus();
            }
          }
        });
      });
    });
  }
};

// ContextMenu component hook
export const ContextMenu = {
  mounted() {
    const trigger = this.el.querySelector('[role="menu"]').previousElementSibling;
    const menu = this.el.querySelector('[role="menu"]');

    this.handleContextMenu = (e) => {
      e.preventDefault();

      menu.style.left = `${e.clientX}px`;
      menu.style.top = `${e.clientY}px`;
      menu.classList.remove('hidden');
    };

    this.handleClickOutside = (e) => {
      if (!menu.contains(e.target)) {
        menu.classList.add('hidden');
      }
    };

    trigger.addEventListener('contextmenu', this.handleContextMenu);
    document.addEventListener('click', this.handleClickOutside);
  },
  destroyed() {
    const trigger = this.el.querySelector('[role="menu"]').previousElementSibling;
    if (trigger) {
      trigger.removeEventListener('contextmenu', this.handleContextMenu);
    }
    document.removeEventListener('click', this.handleClickOutside);
  }
};

// Combobox component hook
export const Combobox = {
  mounted() {
    this.handleClickOutside = (e) => {
      if (!this.el.contains(e.target)) {
        const dropdown = this.el.querySelector('[role="listbox"]');
        if (dropdown && !dropdown.classList.contains('hidden')) {
          dropdown.classList.add('hidden');
        }
      }
    };
    document.addEventListener('click', this.handleClickOutside);
  },
  destroyed() {
    document.removeEventListener('click', this.handleClickOutside);
  }
};

// Command component hook
export const Command = {
  mounted() {
    const input = this.el.querySelector('input[type="text"]');
    const items = this.el.querySelectorAll('[role="menuitem"], button');

    if (!input) return;

    this.handleInput = () => {
      const searchTerm = input.value.toLowerCase();

      items.forEach(item => {
        const text = item.textContent.toLowerCase();
        const parent = item.closest('[class*="overflow-hidden"]');

        if (text.includes(searchTerm)) {
          item.style.display = '';
          if (parent) parent.style.display = '';
        } else {
          item.style.display = 'none';
        }
      });

      // Hide empty groups
      const groups = this.el.querySelectorAll('[class*="overflow-hidden"]');
      groups.forEach(group => {
        const visibleItems = Array.from(group.querySelectorAll('button')).filter(
          item => item.style.display !== 'none'
        );
        group.style.display = visibleItems.length > 0 ? '' : 'none';
      });
    };

    input.addEventListener('input', this.handleInput);

    // Keyboard navigation
    this.handleKeydown = (e) => {
      const visibleItems = Array.from(items).filter(item => item.style.display !== 'none');
      const currentIndex = visibleItems.indexOf(document.activeElement);

      if (e.key === 'ArrowDown') {
        e.preventDefault();
        const nextIndex = (currentIndex + 1) % visibleItems.length;
        visibleItems[nextIndex]?.focus();
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        const prevIndex = currentIndex <= 0 ? visibleItems.length - 1 : currentIndex - 1;
        visibleItems[prevIndex]?.focus();
      }
    };

    this.el.addEventListener('keydown', this.handleKeydown);
  },
  destroyed() {
    const input = this.el.querySelector('input[type="text"]');
    if (input) {
      input.removeEventListener('input', this.handleInput);
    }
    this.el.removeEventListener('keydown', this.handleKeydown);
  }
};

// Calendar component hook
export const Calendar = {
  mounted() {
    // Calendar logic would be implemented here
    // For full implementation, consider using a library like date-fns
  }
};

// Carousel component hook
export const Carousel = {
  mounted() {
    this.currentIndex = 0;
    this.items = this.el.querySelectorAll('[data-carousel-item]');
    this.autoPlay = this.el.dataset.autoPlay === 'true';
    this.interval = parseInt(this.el.dataset.interval || 3000);

    this.showSlide = (index) => {
      this.items.forEach((item, i) => {
        if (i === index) {
          item.classList.remove('hidden');
          item.classList.add('block');
        } else {
          item.classList.add('hidden');
          item.classList.remove('block');
        }
      });

      // Update indicators
      const indicators = this.el.querySelectorAll('[aria-label^="Go to slide"]');
      indicators.forEach((indicator, i) => {
        if (i === index) {
          indicator.classList.add('bg-white');
          indicator.classList.remove('bg-white/50');
        } else {
          indicator.classList.remove('bg-white');
          indicator.classList.add('bg-white/50');
        }
      });

      this.currentIndex = index;
    };

    this.next = () => {
      const nextIndex = (this.currentIndex + 1) % this.items.length;
      this.showSlide(nextIndex);
    };

    this.prev = () => {
      const prevIndex = this.currentIndex === 0 ? this.items.length - 1 : this.currentIndex - 1;
      this.showSlide(prevIndex);
    };

    // Listen for custom events
    this.handleCarouselEvent = (e) => {
      if (e.type === 'carousel:next') this.next();
      if (e.type === 'carousel:prev') this.prev();
      if (e.type === 'carousel:goto') this.showSlide(e.detail.index);
    };

    this.el.addEventListener('carousel:next', this.handleCarouselEvent);
    this.el.addEventListener('carousel:prev', this.handleCarouselEvent);
    this.el.addEventListener('carousel:goto', this.handleCarouselEvent);

    // Auto play
    if (this.autoPlay) {
      this.autoPlayInterval = setInterval(this.next, this.interval);
    }
  },
  destroyed() {
    if (this.autoPlayInterval) {
      clearInterval(this.autoPlayInterval);
    }
    this.el.removeEventListener('carousel:next', this.handleCarouselEvent);
    this.el.removeEventListener('carousel:prev', this.handleCarouselEvent);
    this.el.removeEventListener('carousel:goto', this.handleCarouselEvent);
  }
};

// Resizable component hook
export const Resizable = {
  mounted() {
    const handles = this.el.querySelectorAll('[data-resize-handle]');

    handles.forEach(handle => {
      let startX, startY, startWidth, startHeight;
      let leftPanel, rightPanel;

      const handleMouseDown = (e) => {
        e.preventDefault();
        startX = e.clientX;
        startY = e.clientY;

        leftPanel = handle.previousElementSibling;
        rightPanel = handle.nextElementSibling;

        if (leftPanel && rightPanel) {
          startWidth = leftPanel.offsetWidth;

          document.addEventListener('mousemove', handleMouseMove);
          document.addEventListener('mouseup', handleMouseUp);
        }
      };

      const handleMouseMove = (e) => {
        if (!leftPanel || !rightPanel) return;

        const diff = e.clientX - startX;
        const newWidth = startWidth + diff;

        leftPanel.style.flex = 'none';
        leftPanel.style.width = `${newWidth}px`;
      };

      const handleMouseUp = () => {
        document.removeEventListener('mousemove', handleMouseMove);
        document.removeEventListener('mouseup', handleMouseUp);
      };

      handle.addEventListener('mousedown', handleMouseDown);
    });
  }
};

// Toast component hook
export const Toast = {
  mounted() {
    const duration = parseInt(this.el.dataset.duration || 5000);

    if (duration > 0) {
      this.timeout = setTimeout(() => {
        this.el.classList.add('animate-out', 'fade-out', 'slide-out-to-top-full');
        setTimeout(() => {
          this.el.remove();
        }, 300);
      }, duration);
    }
  },
  destroyed() {
    if (this.timeout) {
      clearTimeout(this.timeout);
    }
  }
};

// Export all hooks as a single object
export default {
  Select,
  Slider,
  InputOTP,
  ContextMenu,
  Combobox,
  Command,
  Calendar,
  Carousel,
  Resizable,
  Toast
};
