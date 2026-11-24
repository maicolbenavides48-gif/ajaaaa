import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './src/App.tsx';
import './index.css';
import { registerSW } from './src/sw-register';

registerSW();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
